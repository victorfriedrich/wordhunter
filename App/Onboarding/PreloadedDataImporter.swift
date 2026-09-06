import Foundation
import UIKit

@available(iOS 18.0, *)
@MainActor
final class PreloadedDataImporter {

    static func importPreloadedData(
        language: Language,
        wordStore: WordStore,
        achievementEngine: AchievementEngine,
        settings: AppSettings,
        captureStore: CaptureStore,
        thumbnailStore: ThumbnailStore
    ) async {

        let vocabAssetName = resolveAssetName(base: "PreloadVocabulary", language: language)
        guard let vocabAsset = NSDataAsset(name: vocabAssetName) else { return }

        let portableWords: [PortableWordItem]
        do {
            let decoder = JSONDecoder()

            // First try decoding without touching the data
            do {
                portableWords = try decoder.decode([PortableWordItem].self, from: vocabAsset.data)
            } catch {
                // If the data is in a legacy mixed format, normalize timestamps to Double and retry
                let normalized = try normalizeVocabularyTimestampsToDouble(vocabAsset.data)
                portableWords = try decoder.decode([PortableWordItem].self, from: normalized)
            }
        } catch {
            return
        }

        wordStore.importItems(portableWords)

        let achieveAssetName = resolveAssetName(base: "PreloadAchievements", language: language)
        if let achieveAsset = NSDataAsset(name: achieveAssetName),
           let ids = try? JSONDecoder().decode([String].self, from: achieveAsset.data) {
            let achievementIds = ids.compactMap { AchievementId(rawValue: $0) }
            achievementEngine.importAchievements(achievementIds)
        }

        achievementEngine.reinitializeAfterImport(words: wordStore.allItems(for: settings.sourceLanguage))

        let captureIds = Set(portableWords.flatMap { $0.captureRefs.map(\.captureId) })
        var loadedCaptures: [UUID: UIImage] = [:]

        for captureId in captureIds {
            let assetName = "PreloadCapture_\(captureId.uuidString)"
            if let image = UIImage(named: assetName) {
                captureStore.save(image, id: captureId)
                loadedCaptures[captureId] = image
            }
        }

        for word in portableWords {
            for ref in word.captureRefs {
                guard let captureImage = loadedCaptures[ref.captureId] else { continue }
                await thumbnailStore.save(
                    from: captureImage,
                    bounds: ref.bounds,
                    captureId: ref.captureId
                )
            }
        }
    }

    // MARK: - Normalization

    /// Ensures these fields are Doubles:
    /// - firstSeen, lastSeen
    /// - captureRefs[].capturedAt
    ///
    /// Converts numeric strings like "792174740.789023" into 792174740.789023.
    private static func normalizeVocabularyTimestampsToDouble(_ data: Data) throws -> Data {
        let json = try JSONSerialization.jsonObject(with: data, options: [])

        guard var array = json as? [[String: Any]] else {
            return data
        }

        for i in array.indices {
            coerceToDouble("firstSeen", in: &array[i])
            coerceToDouble("lastSeen", in: &array[i])

            if var refs = array[i]["captureRefs"] as? [[String: Any]] {
                for r in refs.indices {
                    coerceToDouble("capturedAt", in: &refs[r])
                }
                array[i]["captureRefs"] = refs
            }
        }

        return try JSONSerialization.data(withJSONObject: array, options: [])
    }

    private static func coerceToDouble(_ key: String, in dict: inout [String: Any]) {
        guard let value = dict[key] else { return }

        if let d = value as? Double {
            dict[key] = d
            return
        }
        if let n = value as? NSNumber {
            dict[key] = n.doubleValue
            return
        }
        if let s = value as? String {
            // Accept both "792174740.789023" and "792174740,789023" just in case
            let normalized = s.replacingOccurrences(of: ",", with: ".")
            if let d = Double(normalized) {
                dict[key] = d
            }
        }
    }

    // MARK: - Helpers

    private static func resolveAssetName(base: String, language: Language) -> String {
        let suffixed = "\(base)_\(language.rawValue)"
        if NSDataAsset(name: suffixed) != nil { return suffixed }
        return base
    }
}
