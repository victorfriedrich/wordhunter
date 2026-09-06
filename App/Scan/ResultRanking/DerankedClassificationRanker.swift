import Foundation
import UIKit
import os

/// Loads per-label deranking weights produced by `derive_weights.py`
/// and applies them during classification ranking.
///
/// Weight file format (placed in Media.xcassets as `classification_deranking_weights`):
/// ```
/// {
///   "meta": { ... },
///   "weights": {
///     "bottle": 1.0,
///     "structure": 0.42,
///     ...
///   }
/// }
/// ```
///
/// Labels not present in the weights dictionary are treated as 1.0 (no change).
/// Translations that begin with a language article (e.g. "el gato", "die Katze")
/// receive a boost, matching the preference shown in the scan result view.
struct DerankedClassificationRanker: CandidateRanker {

    /// Per-originLabel weight (0.3 ... 1.0). Missing labels default to 1.0.
    private let weights: [String: Double]

    /// The target language, used for article-boost detection.
    private let language: Language

    /// How much to boost candidates whose translation starts with an article.
    /// A value of 1.15 means +15 % on the rank score.
    private let articleBoost: Double

    // MARK: - Initialisation

    /// Designated initialiser.
    /// - Parameters:
    ///   - weights: Label â†’ multiplier dictionary (values in 0 â€¦1).
    ///   - language: The learner's target language.
    ///   - articleBoost: Multiplier for translations that start with an article (default 1.15).
    init(weights: [String: Double] = [:], language: Language, articleBoost: Double = 1.15) {
        self.weights = weights
        self.language = language
        self.articleBoost = articleBoost
    }

    /// Convenience: loads weights from the asset catalog and builds the ranker.
    /// Falls back to empty weights (all 1.0) if the asset is missing or malformed.
    init(language: Language, articleBoost: Double = 1.15) {
        let loaded = Self.loadWeights()
        self.init(weights: loaded, language: language, articleBoost: articleBoost)
    }

    // MARK: - CandidateRanker

    func rank(_ candidates: [ScanCandidate]) -> [ScanCandidate] {
        var ranked = candidates

        for i in ranked.indices {
            var score = Double(ranked[i].confidence)

            // 1. Deranking weight from log analysis
            if let originLabel = ranked[i].originLabel {
                let w = weights[originLabel] ?? weights[originLabel.lowercased()] ?? 1.0
                score *= w
            }

            // 2. Article boost â€“ prefer translations like "el gato" over bare "gato"
            if let translation = ranked[i].translation, language.hasLeadingArticle(in: translation) {
                score *= articleBoost
            }

            ranked[i].rankScore = score
        }

        return ranked.sorted { $0.rankScore > $1.rankScore }
    }

    // MARK: - Weight loading

    private static let assetName = "classification_deranking_weights"

    /// Loads the `"weights"` dictionary from the asset catalog.
    /// Returns an empty dictionary on any failure.
    private static func loadWeights() -> [String: Double] {
        guard let asset = NSDataAsset(name: assetName) else {
            Log.scan.error("Deranking weights asset '\(assetName, privacy: .public)' not found")
            return [:]
        }

        do {
            let root = try JSONSerialization.jsonObject(with: asset.data) as? [String: Any]
            let raw = root?["weights"] as? [String: Any] ?? [:]

            var result: [String: Double] = [:]
            for (key, value) in raw {
                if let d = value as? Double {
                    result[key] = d
                } else if let n = value as? NSNumber {
                    result[key] = n.doubleValue
                }
            }
            return result
        } catch {
            Log.scan.error("Failed to parse deranking weights: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }
}
