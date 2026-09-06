import Foundation
import UIKit


// This is primarily used to generate the weights for DerankedClassificationRanker

/// Logs classification data for analysis and debugging.
/// Uses JSONL (one JSON object per line) for O(1) append instead of
/// loading/re-encoding the entire history on every scan.
@MainActor
final class ClassificationLogger {
    static let shared = ClassificationLogger()
    
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    /// In-memory cache of entries, loaded lazily on first read.
    private var cachedEntries: [LogEntry]?
    
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("classification_log.jsonl")
        
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // No prettyPrinted — JSONL requires single-line entries
        encoder.outputFormatting = [.sortedKeys]
        
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Log Entry
    
    struct LogEntry: Codable {
        let timestamp: Date
        let captureId: String
        
        /// All classification labels returned by Vision, with confidence scores
        let allClassifications: [ClassificationItem]
        
        /// The words the user actually selected/saved
        let selectedWords: [SelectedWord]
    }
    
    struct ClassificationItem: Codable {
        let label: String
        let confidence: Float
    }
    
    struct SelectedWord: Codable {
        let lemma: String
        let translation: String?
        let source: String  // "classification" or "ocr"
        
        let originLabel: String?
    }
    
    // MARK: - Logging
    
    /// Log a classification event when words are saved.
    func log(
        captureId: UUID,
        rawClassifications: [(label: String, confidence: Float)],
        selectedCandidates: [ScanCandidate]
    ) {
        let entry = LogEntry(
            timestamp: Date(),
            captureId: captureId.uuidString,
            allClassifications: rawClassifications.map { item in
                ClassificationItem(
                    label: item.label,
                    confidence: item.confidence
                )
            },
            selectedWords: selectedCandidates.map { candidate in
                SelectedWord(
                    lemma: candidate.lemma,
                    translation: candidate.translation,
                    source: candidate.source.rawValue,
                    originLabel: candidate.originLabel
                )
            }
        )
        
        appendEntry(entry)
    }
    
    // MARK: - Persistence
    
    /// Append a single entry as one JSONL line — O(1) regardless of log size.
    private func appendEntry(_ entry: LogEntry) {
        guard var data = try? encoder.encode(entry) else { return }
        data.append(contentsOf: [UInt8(ascii: "\n")])
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
        
        // Update in-memory cache if it's been loaded
        cachedEntries?.append(entry)
    }
    
    private func loadEntries() -> [LogEntry] {
        if let cached = cachedEntries { return cached }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cachedEntries = []
            return []
        }
        
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = contents.components(separatedBy: "\n").filter { !$0.isEmpty }
            let entries = lines.compactMap { line -> LogEntry? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(LogEntry.self, from: data)
            }
            cachedEntries = entries
            return entries
        } catch {
            cachedEntries = []
            return []
        }
    }
    
    // MARK: - Analysis Helpers
    
    /// Get all logged entries for analysis
    func getAllEntries() -> [LogEntry] {
        loadEntries()
    }
    
    /// Get frequency counts of all classification labels across all logs
    func getClassificationFrequencies() -> [(label: String, count: Int, avgConfidence: Float)] {
        let entries = loadEntries()
        
        var labelStats: [String: (count: Int, totalConfidence: Float)] = [:]
        
        for entry in entries {
            for classification in entry.allClassifications {
                let existing = labelStats[classification.label] ?? (count: 0, totalConfidence: 0)
                labelStats[classification.label] = (
                    count: existing.count + 1,
                    totalConfidence: existing.totalConfidence + classification.confidence
                )
            }
        }
        
        return labelStats
            .map { (label: $0.key, count: $0.value.count, avgConfidence: $0.value.totalConfidence / Float($0.value.count)) }
            .sorted { $0.count > $1.count }
    }
    
    /// Get labels that appear frequently but are rarely selected
    func getSuggestedFilters(minAppearances: Int = 5, maxSelectionRate: Float = 0.1) -> [String] {
        let entries = loadEntries()

        var labelAppearances: [String: Int] = [:]
        var labelSelections: [String: Int] = [:]

        for entry in entries {
            // appearances are keyed by classification label
            for classification in entry.allClassifications {
                labelAppearances[classification.label, default: 0] += 1
            }

            // selections should be keyed by the same label namespace
            for selected in entry.selectedWords where selected.source == "classification" {
                let key = (selected.originLabel ?? selected.lemma).lowercased()
                labelSelections[key, default: 0] += 1
            }
        }

        return labelAppearances
            .filter { $0.value >= minAppearances }
            .filter { label, appearances in
                let selections = labelSelections[label.lowercased()] ?? 0
                let selectionRate = Float(selections) / Float(appearances)
                return selectionRate <= maxSelectionRate
            }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }
    
    /// Clear all logged entries
    func clearLog() {
        try? FileManager.default.removeItem(at: fileURL)
        cachedEntries = nil
    }
    
    /// Export log as a string for sharing/copying
    func exportLogAsString() -> String {
        let entries = loadEntries()
        
        var output = "Classification Log Export\n"
        output += "Generated: \(Date())\n"
        output += "Total Entries: \(entries.count)\n"
        output += String(repeating: "=", count: 50) + "\n\n"
        
        for (index, entry) in entries.enumerated() {
            output += "[\(index + 1)] \(entry.timestamp)\n"
            output += "Capture: \(entry.captureId)\n"
            output += "Classifications (\(entry.allClassifications.count)):\n"
            
            for classification in entry.allClassifications.prefix(20) {
                output += "  - \(classification.label): \(String(format: "%.2f", classification.confidence))\n"
            }
            
            if entry.allClassifications.count > 20 {
                output += "  ... and \(entry.allClassifications.count - 20) more\n"
            }
            
            output += "Selected (\(entry.selectedWords.count)):\n"
            for selected in entry.selectedWords {
                let trans = selected.translation ?? "-"
                output += "  ✓ \(selected.lemma) (\(trans)) [\(selected.source)]\n"
            }
            
            output += "\n"
        }
        
        // Add frequency analysis
        output += String(repeating: "=", count: 50) + "\n"
        output += "FREQUENCY ANALYSIS\n"
        output += String(repeating: "=", count: 50) + "\n\n"
        
        let frequencies = getClassificationFrequencies()
        output += "Top 50 Most Common Labels:\n"
        for (index, freq) in frequencies.prefix(50).enumerated() {
            output += "\(index + 1). \(freq.label): \(freq.count)x (avg conf: \(String(format: "%.2f", freq.avgConfidence)))\n"
        }
        
        output += "\nSuggested Filters (common but rarely selected):\n"
        for label in getSuggestedFilters() {
            output += "  - \(label)\n"
        }
        
        return output
    }
}
