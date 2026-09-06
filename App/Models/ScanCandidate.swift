import Foundation

/// A word candidate produced by the scan pipeline.
struct ScanCandidate: Identifiable, Hashable {
    var id: String { "\(language.rawValue)::\(lemma.lowercased())" }
    
    let language: Language
    let lemma: String
    let translation: String?
    let source: CandidateSource
    let bounds: CGRect?         // Normalized bounds within capture (nil for scene-level classification)
    let confidence: Float
    
    let originLabel: String?
    
    var rankScore: Double = 0   // Set by ranker
}
