import Foundation
import UIKit
import ZIPFoundation
import os

// MARK: - Export Manifest

struct ExportManifest: Codable {
    let version: Int
    let exportDate: Date
    let wordCount: Int
    let captureCount: Int
    let thumbnailCount: Int
    let achievementCount: Int
    let settings: ExportedSettings
}

struct ExportedSettings: Codable {
    let sourceLanguage: String
    let showTranslation: Bool
    let showCategories: Bool
}

// MARK: - Portable Word Item (for JSON export/import)

/// A Codable snapshot of a WordItem + its CaptureReferences, used for file-based export/import.
struct PortableWordItem: Codable {
    let language: Language
    var lemma: String
    var translation: String?
    var sources: Set<CandidateSource>
    var captureRefs: [PortableCaptureReference]
    var occurrences: Int
    var firstSeen: Date
    var lastSeen: Date
}

struct PortableCaptureReference: Codable {
    let captureId: UUID
    let bounds: CGRect
    let capturedAt: Date
    let location: CapturedLocation?
}

// MARK: - Export/Import Manager

@available(iOS 18.0, *)
@MainActor
final class ExportImportManager {

    enum ExportError: LocalizedError {
        case archiveCreationFailed
        case noDataToExport
        case writeError(String)

        var errorDescription: String? {
            switch self {
            case .archiveCreationFailed: return "Failed to create archive."
            case .noDataToExport: return "No data to export."
            case .writeError(let detail): return "Write failed: \(detail)"
            }
        }
    }

    enum ImportError: LocalizedError {
        case invalidArchive
        case manifestMissing
        case manifestCorrupted
        case unsupportedVersion(Int)
        case extractionFailed(String)
        case vocabularyCorrupted(String)

        var errorDescription: String? {
            switch self {
            case .invalidArchive: return "The file is not a valid export archive."
            case .manifestMissing: return "Export manifest not found in archive."
            case .manifestCorrupted: return "Export manifest is corrupted."
            case .unsupportedVersion(let v): return "Unsupported export version: \(v)."
            case .extractionFailed(let d): return "Extraction failed: \(d)"
            case .vocabularyCorrupted(let d): return "Vocabulary data corrupted: \(d)"
            }
        }
    }

    private static let currentVersion = 1

    private let fm = FileManager.default

    private var docsDir: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Export

    func exportData(
        wordStore: WordStore,
        achievementEngine: AchievementEngine,
        settings: AppSettings
    ) throws -> URL {

        let words = wordStore.allItems(for: settings.sourceLanguage)
        guard !words.isEmpty else { throw ExportError.noDataToExport }

        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // 1. vocabulary.json â€” serialize SwiftData models to portable JSON
        let portableWords = words.map { item in
            PortableWordItem(
                language: item.language,
                lemma: item.lemma,
                translation: item.translation,
                sources: item.sources,
                captureRefs: item.captureRefs.map { ref in
                    PortableCaptureReference(
                        captureId: ref.captureId,
                        bounds: ref.bounds,
                        capturedAt: ref.capturedAt,
                        location: ref.location
                    )
                },
                occurrences: item.occurrences,
                firstSeen: item.firstSeen,
                lastSeen: item.lastSeen
            )
        }
        // Fix #22: Use iso8601 consistently for vocabulary dates (matching manifest format)
        let vocabEncoder = JSONEncoder()
        vocabEncoder.dateEncodingStrategy = .iso8601
        let vocabData = try vocabEncoder.encode(portableWords)
        try vocabData.write(to: tempDir.appendingPathComponent("vocabulary.json"))

        // 2. achievements.json
        let unlockedIds = achievementEngine.unlockedIds.map { $0.rawValue }
        let achieveData = try JSONEncoder().encode(unlockedIds)
        try achieveData.write(to: tempDir.appendingPathComponent("achievements.json"))

        // 3. Captures/
        let capturesDir = tempDir.appendingPathComponent("Captures", isDirectory: true)
        try fm.createDirectory(at: capturesDir, withIntermediateDirectories: true)

        let captureIds = Set(words.flatMap { $0.captureRefs.map { $0.captureId } })
        var capturesCopied = 0
        for id in captureIds {
            let src = docsDir.appendingPathComponent("Captures/\(id.uuidString).jpg")
            if fm.fileExists(atPath: src.path) {
                try fm.copyItem(at: src, to: capturesDir.appendingPathComponent("\(id.uuidString).jpg"))
                capturesCopied += 1
            }
        }

        // 4. Thumbnails/
        let thumbsDir = tempDir.appendingPathComponent("Thumbnails", isDirectory: true)
        try fm.createDirectory(at: thumbsDir, withIntermediateDirectories: true)

        let thumbsSrc = docsDir.appendingPathComponent("Thumbnails", isDirectory: true)
        var thumbsCopied = 0
        if let thumbFiles = try? fm.contentsOfDirectory(at: thumbsSrc, includingPropertiesForKeys: nil) {
            for file in thumbFiles where file.pathExtension == "jpg" {
                try fm.copyItem(at: file, to: thumbsDir.appendingPathComponent(file.lastPathComponent))
                thumbsCopied += 1
            }
        }

        // 5. manifest.json
        let manifest = ExportManifest(
            version: Self.currentVersion,
            exportDate: .now,
            wordCount: words.count,
            captureCount: capturesCopied,
            thumbnailCount: thumbsCopied,
            achievementCount: unlockedIds.count,
            settings: ExportedSettings(
                sourceLanguage: settings.sourceLanguage.rawValue,
                showTranslation: settings.showTranslation,
                showCategories: settings.showCategories
            )
        )
        let manifestData = try JSONEncoder.manifestEncoder.encode(manifest)
        try manifestData.write(to: tempDir.appendingPathComponent("manifest.json"))

        // 6. Create zip
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: .now)
        let zipName = "WordLens_Export_\(timestamp).zip"
        let zipURL = fm.temporaryDirectory.appendingPathComponent(zipName)

        try? fm.removeItem(at: zipURL)
        try fm.zipItem(at: tempDir, to: zipURL, shouldKeepParent: false)

        return zipURL
    }

    // MARK: - Import

    struct ImportSummary {
        let wordsImported: Int
        let capturesImported: Int
        let thumbnailsImported: Int
        let achievementsImported: Int
    }

    func importData(
        from zipURL: URL,
        wordStore: WordStore,
        achievementEngine: AchievementEngine,
        settings: AppSettings
    ) throws -> ImportSummary {

        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        do {
            try fm.unzipItem(at: zipURL, to: tempDir)
        } catch {
            Log.transfer.error("ZIP extraction failed: \(error.localizedDescription, privacy: .public)")
            throw ImportError.invalidArchive
        }

        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            Log.transfer.error("manifest.json missing from archive")
            throw ImportError.manifestMissing
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest: ExportManifest
        do {
            manifest = try JSONDecoder.manifestDecoder.decode(ExportManifest.self, from: manifestData)
        } catch {
            Log.transfer.error("Manifest decode failed: \(error.localizedDescription, privacy: .public)")
            throw ImportError.manifestCorrupted
        }

        guard manifest.version <= Self.currentVersion else {
            throw ImportError.unsupportedVersion(manifest.version)
        }

        // Import vocabulary
        let vocabURL = tempDir.appendingPathComponent("vocabulary.json")
        var wordsImported = 0
        if fm.fileExists(atPath: vocabURL.path) {
            let vocabData = try Data(contentsOf: vocabURL)
            let portable: [PortableWordItem]
            do {
                portable = try Self.decodeVocabulary(from: vocabData)
            } catch {
                Log.transfer.error("Vocabulary decode failed: \(Self.describe(error), privacy: .public)")
                throw ImportError.vocabularyCorrupted("\(error)")
            }
            wordStore.importItems(portable)
            wordsImported = portable.count
        }

        // Import achievements
        let achieveURL = tempDir.appendingPathComponent("achievements.json")
        var achievementsImported = 0
        if fm.fileExists(atPath: achieveURL.path) {
            let achieveData = try Data(contentsOf: achieveURL)
            let ids = (try? JSONDecoder().decode([String].self, from: achieveData)) ?? []
            // Fix #11: Actually restore achievement unlocks
            let achievementIds = ids.compactMap { AchievementId(rawValue: $0) }
            achievementEngine.importAchievements(achievementIds)
            achievementsImported = ids.count
        }

        // Import captures
        let capturesSrc = tempDir.appendingPathComponent("Captures", isDirectory: true)
        let capturesDest = docsDir.appendingPathComponent("Captures", isDirectory: true)
        var capturesImported = 0
        try fm.createDirectory(at: capturesDest, withIntermediateDirectories: true)

        if let captureFiles = try? fm.contentsOfDirectory(at: capturesSrc, includingPropertiesForKeys: nil) {
            for file in captureFiles where file.pathExtension == "jpg" {
                let dest = capturesDest.appendingPathComponent(file.lastPathComponent)
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: file, to: dest)
                capturesImported += 1
            }
        }

        // Import thumbnails
        let thumbsSrc = tempDir.appendingPathComponent("Thumbnails", isDirectory: true)
        let thumbsDest = docsDir.appendingPathComponent("Thumbnails", isDirectory: true)
        var thumbnailsImported = 0
        try fm.createDirectory(at: thumbsDest, withIntermediateDirectories: true)

        if let thumbFiles = try? fm.contentsOfDirectory(at: thumbsSrc, includingPropertiesForKeys: nil) {
            for file in thumbFiles where file.pathExtension == "jpg" {
                let dest = thumbsDest.appendingPathComponent(file.lastPathComponent)
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: file, to: dest)
                thumbnailsImported += 1
            }
        }

        // Fix #11: Reinitialize achievement engine with new words
        achievementEngine.reinitializeAfterImport(words: wordStore.allItems(for: settings.sourceLanguage))

        // Restore settings
        if let lang = Language(rawValue: manifest.settings.sourceLanguage) {
            settings.sourceLanguage = lang
        }
        settings.showTranslation = manifest.settings.showTranslation
        settings.showCategories = manifest.settings.showCategories

        return ImportSummary(
            wordsImported: wordsImported,
            capturesImported: capturesImported,
            thumbnailsImported: thumbnailsImported,
            achievementsImported: achievementsImported
        )
    }

    // MARK: - Diagnostics

    /// Flattens a `DecodingError` into a single line naming the failing key path,
    /// which is the part that actually identifies a bad import file.
    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return error.localizedDescription
        }
        func path(_ ctx: DecodingError.Context) -> String {
            let joined = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            return joined.isEmpty ? "<root>" : joined
        }
        switch decoding {
        case .typeMismatch(let type, let ctx):
            return "typeMismatch: expected \(type) at \(path(ctx)) — \(ctx.debugDescription)"
        case .valueNotFound(let type, let ctx):
            return "valueNotFound: \(type) at \(path(ctx)) — \(ctx.debugDescription)"
        case .keyNotFound(let key, let ctx):
            return "keyNotFound: \(key.stringValue) at \(path(ctx)) — \(ctx.debugDescription)"
        case .dataCorrupted(let ctx):
            return "dataCorrupted at \(path(ctx)) — \(ctx.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    // MARK: - Vocabulary Decoding (backward-compatible)

    private static func decodeVocabulary(from data: Data) throws -> [PortableWordItem] {
        // Try 1: Current format — iso8601 dates, CGRect as [x,y,w,h]
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([PortableWordItem].self, from: data)
        } catch {
            // Not current format, try legacy
        }

        // Try 2: Legacy dates (numeric timeIntervalSinceReferenceDate), CGRect as [x,y,w,h]
        // This handles exports from before Fix #22 that already had flat bounds
        do {
            return try JSONDecoder().decode([PortableWordItem].self, from: data)
        } catch {
            // Bounds might be in legacy nested format, normalize them
        }

        // Try 3: Legacy dates + legacy bounds [[x,y],[w,h]] -> [x,y,w,h]
        return try decodeLegacyVocabulary(from: data)
    }

    /// Normalizes legacy `[[x,y],[w,h]]` bounds to `[x,y,w,h]` and decodes
    /// with default date strategy (handles numeric timestamps).
    private static func decodeLegacyVocabulary(from data: Data) throws -> [PortableWordItem] {
        guard var items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Expected array of objects")
            )
        }

        for i in items.indices {
            guard var refs = items[i]["captureRefs"] as? [[String: Any]] else { continue }
            for j in refs.indices {
                if let nested = refs[j]["bounds"] as? [[NSNumber]], nested.count == 2,
                   nested[0].count == 2, nested[1].count == 2 {
                    // Convert [[x,y],[w,h]] to flat [x, y, w, h]
                    refs[j]["bounds"] = [
                        nested[0][0].doubleValue, nested[0][1].doubleValue,
                        nested[1][0].doubleValue, nested[1][1].doubleValue
                    ] as [Double]
                }
            }
            items[i]["captureRefs"] = refs
        }

        let normalizedData = try JSONSerialization.data(withJSONObject: items)
        return try JSONDecoder().decode([PortableWordItem].self, from: normalizedData)
    }
}

// MARK: - Encoder / Decoder helpers

private extension JSONEncoder {
    static let manifestEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

private extension JSONDecoder {
    static let manifestDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
