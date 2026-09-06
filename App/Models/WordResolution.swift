import Foundation
import CoreGraphics

struct WordResolution: Hashable, Codable {
    let observed: String
    let normalized: String
    let language: Language
    let lemma: String
    let translation: String?
    let bounds: CGRect?

    init(
        observed: String,
        normalized: String,
        language: Language,
        lemma: String,
        translation: String? = nil,
        bounds: CGRect? = nil
    ) {
        self.observed = observed
        self.normalized = normalized
        self.language = language
        self.lemma = lemma
        self.translation = translation
        self.bounds = bounds
    }
}
