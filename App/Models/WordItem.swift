import Foundation
import SwiftData

@available(iOS 18, *)
@Model
final class WordItem {
    #Unique<WordItem>([\.languageRaw, \.lemma])
    #Index<WordItem>([\.languageRaw, \.lemma, \.lastSeen])

    var languageRaw: String
    var lemma: String

    var language: Language {
        get { Language(rawValue: languageRaw) ?? .spanish }
        set { languageRaw = newValue.rawValue }
    }

    /// Stable string identifier for use outside SwiftData (gallery, selection sets, etc.)
    var stableId: String { "\(languageRaw)::\(lemma)" }
    var translation: String?
    var sourcesRaw: Set<String>

    var sources: Set<CandidateSource> {
        get { Set(sourcesRaw.compactMap { CandidateSource(rawValue: $0) }) }
        set { sourcesRaw = Set(newValue.map(\.rawValue)) }
    }

    @Relationship(deleteRule: .cascade, inverse: \CaptureReference.word)
    var captureRefs: [CaptureReference] = []

    var occurrences: Int
    var firstSeen: Date
    var lastSeen: Date

    var latestCaptureRef: CaptureReference? {
        captureRefs.max(by: { $0.capturedAt < $1.capturedAt })
    }

    /// Lemma with article stripped and diacritics folded, for alphabetical sorting.
    var sortableLemma: String {
        language.strippingArticle(from: lemma).foldedForSearch
    }

    init(
        language: Language,
        lemma: String,
        translation: String? = nil,
        sources: Set<CandidateSource> = [],
        occurrences: Int = 1,
        firstSeen: Date = .now,
        lastSeen: Date = .now
    ) {
        self.languageRaw = language.rawValue
        self.lemma = lemma
        self.translation = translation
        self.sourcesRaw = Set(sources.map(\.rawValue))
        self.occurrences = occurrences
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}
