import Foundation

struct PassthroughLexicon: LexiconResolving {
    func resolve(observed: String, normalized: String, language: Language) -> WordResolution {
        WordResolution(
            observed: observed,
            normalized: normalized,
            language: language,
            lemma: normalized.isEmpty ? observed : normalized,
            translation: nil,
            bounds: nil
        )
    }
}
