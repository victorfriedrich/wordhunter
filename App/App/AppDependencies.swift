import Foundation

// MARK: - Lexicon Provider

/// Provides the appropriate lexicon for the current language setting.
@available(iOS 17.0, *)
@MainActor
@Observable
final class LexiconProvider {

    /// Shared SQLite lexicon (contains all languages)
    private let sqliteLexicon: SQLiteLexicon?

    /// Passthrough for English (no dictionary lookup)
    private let passthroughLexicon = PassthroughLexicon()

    init() {
        self.sqliteLexicon = SQLiteLexicon(assetName: "lexicon")
    }

    func lexicon(for language: Language) -> LexiconResolving {
        switch language {
        case .english:
            return passthroughLexicon
        case .spanish, .french, .german:
            return sqliteLexicon ?? passthroughLexicon
        }
    }

    var sqlite: SQLiteLexicon? {
        sqliteLexicon
    }
}

// MARK: - App Dependencies

@available(iOS 17.0, *)
@MainActor
@Observable
final class AppDependencies {
    let normalizer: TokenNormalizing
    let lexiconProvider: LexiconProvider

    init(
        normalizer: TokenNormalizing = DefaultTokenNormalizer(),
        lexiconProvider: LexiconProvider = LexiconProvider()
    ) {
        self.normalizer = normalizer
        self.lexiconProvider = lexiconProvider
    }

    func lexicon(for settings: AppSettings) -> LexiconResolving {
        lexiconProvider.lexicon(for: settings.sourceLanguage)
    }

    var sqliteLexicon: SQLiteLexicon? {
        lexiconProvider.sqlite
    }
}
