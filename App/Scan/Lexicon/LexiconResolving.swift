import Foundation

protocol LexiconResolving {
    func resolve(observed: String, normalized: String, language: Language) -> WordResolution
}
