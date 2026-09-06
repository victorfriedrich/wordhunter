import Foundation

/// Determines how many candidates to show by default in a section.
protocol DisplayStrategy {
    func visibleCount(for candidates: [ScanCandidate]) -> Int
}

/// Shows a fixed number of candidates.
struct FixedCountStrategy: DisplayStrategy {
    let count: Int
    
    func visibleCount(for candidates: [ScanCandidate]) -> Int {
        min(count, candidates.count)
    }
}

// MARK: - Adaptive OCR Display Strategy

/// Decides how many OCR labels to surface based on whether the photo appears to
/// be "text-heavy" (a sign, poster, newspaper, menu …) vs. a normal scene that
/// contains incidental text.
///
/// Most real-world photos contain only a little readable text.
/// (a street name, a product label). Showing too many OCR words for these images
/// creates noise. But when the user deliberately photographs a text-heavy object,
/// we want to show more words. The `textIntentScore` heuristic combines three
/// noisy signals (text size, word count, photographed object) to create a more reliable decision metric
struct AdaptiveOCRDisplayStrategy: DisplayStrategy {

    /// Classification labels that hint the image depicts a text-heavy subject.
    /// A match gives a small boost — classification is noisy so we don't rely on
    /// it heavily.
    let classificationLabels: [String]

    /// How many OCR tokens resolved successfully against the lexicon.
    let resolvedWordCount: Int

    /// Sum of all OCR bounding-box areas (normalized 0…1 coordinates, so max ≈ 1.0).
    let totalBoundsArea: Double

    /// Threshold above which we treat the image as text-heavy.
    private static let textHeavyThreshold: Double = 0.75

    /// Labels whose presence in classification results suggest the subject is
    /// inherently textual (signs, documents, screens, etc.).
    private static let textHintLabels: Set<String> = [
        "poster", "sign", "newspaper", "menu", "book", "magazine",
        "billboard", "letter", "document"
    ]

    func visibleCount(for candidates: [ScanCandidate]) -> Int {
        let score = textIntentScore
        let limit = score >= Self.textHeavyThreshold ? 8 : 2
        return min(limit, candidates.count)
    }

    /// Composite score (0…1-ish) estimating how "text-heavy" the photo is.
    /// - `labelBoost`:    classification suggests text-heavy word
    private var textIntentScore: Double {
        // Bounds area: Area > ~0.2 starts scoring meaningfully.
        let boundsSignal = min(totalBoundsArea / 0.3, 1.0)

        // Word count: 8+ resolved words is a strong signal.
        let countSignal = min(Double(resolvedWordCount) / 8.0, 1.0)

        // Classification hint: small additive boost (unreliable, so kept low).
        let lowered = Set(classificationLabels.map { $0.lowercased() })
        let hasTextHint = !lowered.isDisjoint(with: Self.textHintLabels)
        let labelBoost: Double = hasTextHint ? 0.25 : 0.0

        return (boundsSignal * 0.5) + (countSignal * 0.5) + labelBoost
    }
}
