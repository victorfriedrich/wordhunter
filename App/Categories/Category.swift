import Foundation

/// A word entry within a category
/// Decodes from a simple string in JSON (e.g., "puerta")
struct CategoryWord: Codable, Identifiable, Hashable, Sendable {
    let lemma: String
    
    var id: String { lemma }
    
    // Decode from a plain string
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.lemma = try container.decode(String.self)
    }
    
    // Encode as a plain string
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(lemma)
    }
    
    init(lemma: String) {
        self.lemma = lemma
    }
}

/// A category containing a list of words to collect (loaded from JSON)
struct WordCategory: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let words: [CategoryWord]
    let imageOnRight: Bool
    
    /// Row configuration for the pyramid layout: 5,4,3,2,2,2,3,4 = 25 total
    static let rowCounts = [5, 4, 3, 2, 2, 2, 3, 4]
    static let maxWords = 25

    /// Cumulative start index for each row, derived from rowCounts.
    static let rowStartIndices: [Int] = {
        var indices: [Int] = []
        var current = 0
        for count in rowCounts {
            indices.append(current)
            current += count
        }
        return indices
    }()
}

/// Lightweight, value-type snapshot of a CaptureReference for use outside SwiftData.
@available(iOS 18, *)
struct CaptureRefSnapshot: Hashable, Sendable, Identifiable {
    let captureId: UUID
    let boundsX: Double
    let boundsY: Double
    let boundsWidth: Double
    let boundsHeight: Double
    let capturedAt: Date

    var id: String { "\(captureId.uuidString)|\(boundsX),\(boundsY),\(boundsWidth),\(boundsHeight)" }

    var bounds: CGRect {
        CGRect(x: boundsX, y: boundsY, width: boundsWidth, height: boundsHeight)
    }

    init(from ref: CaptureReference) {
        self.captureId = ref.captureId
        self.boundsX = ref.boundsX
        self.boundsY = ref.boundsY
        self.boundsWidth = ref.boundsWidth
        self.boundsHeight = ref.boundsHeight
        self.capturedAt = ref.capturedAt
    }
}

/// Progress for a single word within a category
/// Includes the resolved translation from the lexicon (if available)
@available(iOS 18, *)
struct CategoryWordProgress: Identifiable, Hashable, Sendable {
    let word: CategoryWord
    let captureRef: CaptureRefSnapshot?
    let translation: String?  // Resolved from lexicon
    
    var id: String { word.lemma }
    var isUnlocked: Bool { captureRef != nil }
}

/// Progress for an entire category
@available(iOS 18, *)
struct CategoryProgress: Identifiable, Sendable {
    let category: WordCategory
    let wordProgress: [CategoryWordProgress]
    
    var id: String { category.id }
    
    var unlockedCount: Int {
        wordProgress.filter { $0.isUnlocked }.count
    }
    
    var totalCount: Int {
        wordProgress.count
    }
    
}
