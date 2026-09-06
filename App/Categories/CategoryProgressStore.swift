import Foundation
import UIKit
import SwiftData
import os

// MARK: - Category Progress Store

/// Loads dynamically localized categories and computes progress from SwiftData queries.
/// No Combine subscriptions — call `recomputeAllProgress()` after mutations.
@available(iOS 18, *)
@MainActor
@Observable
final class CategoryProgressStore {

    // MARK: - State

    private(set) var categories: [WordCategory] = []
    private(set) var progress: [CategoryProgress] = []

    // MARK: - Private

    /// Lookup table: target lemma -> set of category IDs containing it
    private var lemmaToCategories: [String: Set<String>] = [:]
    
    /// Cached translations from lexicon for the UI: target lemma -> native translation
    private var translationCache: [String: String] = [:]

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let settings: AppSettings
    private let lexicon: SQLiteLexicon?

    // MARK: - Init

    init(modelContext: ModelContext, settings: AppSettings, lexicon: SQLiteLexicon? = nil) {
        self.modelContext = modelContext
        self.settings = settings
        self.lexicon = lexicon
    }

    // MARK: - Async Loading

    func loadInitialData() async {
        let t0 = CFAbsoluteTimeGetCurrent()
        
        // Load the localized category file (e.g., "categories_es" or "categories_en")
        let languageCode = settings.sourceLanguage.databaseCode
        let assetName = "categories_\(languageCode)"

        let loadedCategories = await Task.detached(priority: .userInitiated) {
            // Fallback to "categories" if the localized version isn't found
            guard let asset = NSDataAsset(name: assetName) ?? NSDataAsset(name: "categories") else {
                return [WordCategory]()
            }
            return (try? JSONDecoder().decode([WordCategory].self, from: asset.data)) ?? []
        }.value

        self.categories = loadedCategories
        self.buildLemmaIndex()

        // Fire and forget — runs on GCD, does not block AppState.initialize
        Task {
            await recomputeAllProgressAsync()
        }

        let tTotal = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        Log.boot.debug("[CategoryProgressStore.loadInitialData] Loaded \(assetName, privacy: .public) in: \(String(format: "%.1f", (tTotal-t0)*1000), privacy: .public)ms")
        #endif
    }

    private func buildLemmaIndex() {
        lemmaToCategories.removeAll()
        for category in categories {
            for word in category.words.prefix(WordCategory.maxWords) {
                let key = word.lemma.lowercased()
                lemmaToCategories[key, default: []].insert(category.id)
            }
        }
    }

    // MARK: - Progress Computation

    func recomputeAllProgress() {
        Task {
            await recomputeAllProgressAsync()
        }
    }

    /// Asynchronous core computation logic — all heavy work on GCD.
    private func recomputeAllProgressAsync() async {
        let t0 = CFAbsoluteTimeGetCurrent()

        let language = settings.sourceLanguage
        let languageRaw = language.rawValue
        let localCategories = self.categories
        let localLemmaToCategories = self.lemmaToCategories
        let localLexicon = self.lexicon
        let localModelContainer = modelContext.container

        let (newProgress, newTranslationCache) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {

                let bgContext = ModelContext(localModelContainer)

                // Step 1: Fetch lemmas that are in any category
                var wordFetch = FetchDescriptor<WordItem>(
                    predicate: #Predicate { $0.languageRaw == languageRaw }
                )
                wordFetch.propertiesToFetch = [\.lemma]
                let items = (try? bgContext.fetch(wordFetch)) ?? []

                let categoryLemmaSet = Set(localLemmaToCategories.keys)
                let matchedLemmas = Set(items.map { $0.lemma.lowercased() }.filter { categoryLemmaSet.contains($0) })

                // Step 2: Fetch CaptureReferences directly
                var refFetch = FetchDescriptor<CaptureReference>(
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
                )
                refFetch.propertiesToFetch = [\.captureId, \.boundsX, \.boundsY, \.boundsWidth, \.boundsHeight, \.capturedAt]
                let allRefs = (try? bgContext.fetch(refFetch)) ?? []

                // Step 3: Build lemma -> latest CaptureRefSnapshot
                var collectedLemmas: [String: CaptureRefSnapshot] = [:]
                for ref in allRefs {
                    guard let wordLemma = ref.word?.lemma.lowercased() else { continue }
                    guard matchedLemmas.contains(wordLemma) else { continue }
                    if collectedLemmas[wordLemma] == nil {
                        collectedLemmas[wordLemma] = CaptureRefSnapshot(from: ref)
                    }
                }

                // Step 4: Batch fetch translations for the UI
                var backgroundCache: [String: String] = [:]
                let allLemmas = localCategories.flatMap { $0.words.prefix(WordCategory.maxWords).map { $0.lemma } }

                if let lexicon = localLexicon, !allLemmas.isEmpty {
                    // This fetches English translations for Spanish words, etc.
                    let batchTranslations = lexicon.batchLookupTranslations(lemmas: allLemmas, language: language)
                    for (key, value) in batchTranslations {
                        backgroundCache[key] = value
                    }
                }

                // Step 5: Build final progress structures
                let computedProgress = localCategories.map { category in
                    let wordProgress = category.words.prefix(WordCategory.maxWords).map { word in
                        let key = word.lemma.lowercased()
                        let captureRef = collectedLemmas[key]

                        let cachedVal = backgroundCache[key]
                        let translation = (cachedVal == nil || cachedVal == "") ? nil : cachedVal

                        return CategoryWordProgress(word: word, captureRef: captureRef, translation: translation)
                    }
                    return CategoryProgress(category: category, wordProgress: wordProgress)
                }

                continuation.resume(returning: (computedProgress, backgroundCache))
            }
        }

        self.translationCache = newTranslationCache
        self.progress = newProgress

        let tTotal = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        Log.boot.debug("[CategoryProgressStore.recompute] Completed totally off-main-thread in: \(String(format: "%.1f", (tTotal-t0)*1000), privacy: .public)ms")
        #endif
    }

    func handleLanguageChange() {
        translationCache.removeAll()
        Task {
            // Re-running loadInitialData will automatically load the newly selected language's JSON
            await loadInitialData()
        }
    }

    // MARK: - Queries

    func isInAnyCategory(_ lemma: String) -> Bool {
        lemmaToCategories[lemma.lowercased()] != nil
    }

    func categoryIds(containing lemma: String) -> Set<String> {
        lemmaToCategories[lemma.lowercased()] ?? []
    }

    func progress(forCategoryId id: String) -> CategoryProgress? {
        progress.first { $0.id == id }
    }
}
