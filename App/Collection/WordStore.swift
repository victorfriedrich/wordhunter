import Foundation
import SwiftData

@available(iOS 18, *)
@MainActor
@Observable
final class WordStore {
    private let modelContext: ModelContext

    /// Incremented on every mutation so views can react to changes.
    private(set) var changeCount: Int = 0

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Queries

    func contains(language: Language, lemma: String) -> Bool {
        item(language: language, lemma: lemma) != nil
    }

    func item(language: Language, lemma: String) -> WordItem? {
        let langRaw = language.rawValue
        var descriptor = FetchDescriptor<WordItem>(
            predicate: #Predicate { $0.languageRaw == langRaw && $0.lemma == lemma }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Fetch all items sorted by lastSeen descending, filtered by active language.
    /// Used for export, achievement init, and similar bulk operations.
    func allItems(for language: Language) -> [WordItem] {
        let langRaw = language.rawValue
        let descriptor = FetchDescriptor<WordItem>(
            predicate: #Predicate { $0.languageRaw == langRaw },
            sortBy: [SortDescriptor(\.lastSeen, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Sorted fetch optimized per sort option, filtered by active language.
    ///
    /// - `.dateAdded`: Delegates to SwiftData `SortDescriptor(\.lastSeen)` — no in-memory work.
    /// - `.alphabetic`: Fetches once, computes `sortableLemma` once per item, sorts in-memory.
    ///   This is O(N) string work + O(N log N) comparisons on pre-computed keys — much cheaper
    ///   than the old approach which recomputed `sortableLemma` on every comparison.
    /// - `.pictures`: Fetches once, reads `captureRefs.count` once per item (faults the
    ///   relationship once), sorts in-memory. Acceptable because the count is read, not the refs.
    func sortedItems(by option: WordSortOption, for language: Language) -> [WordItem] {
        let langRaw = language.rawValue
        
        switch option {
        case .dateAdded:
            // SwiftData handles this entirely — no in-memory sort needed
            let descriptor = FetchDescriptor<WordItem>(
                predicate: #Predicate { $0.languageRaw == langRaw },
                sortBy: [SortDescriptor(\.lastSeen, order: .reverse)]
            )
            return (try? modelContext.fetch(descriptor)) ?? []

        case .alphabetic:
            let items = allItems(for: language)
            // Pre-compute sortable keys once, then sort on the cached keys
            let keyed = items.map { ($0, $0.sortableLemma) }
            return keyed.sorted { $0.1 < $1.1 }.map(\.0)

        case .pictures:
            let items = allItems(for: language)
            // .count on the relationship faults the count but not the objects
            return items.sorted { $0.captureRefs.count > $1.captureRefs.count }
        }
    }

    var allCaptureRefs: [CaptureReference] {
        let descriptor = FetchDescriptor<CaptureReference>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Returns the set of all captureIds still referenced by any word.
    func allReferencedCaptureIds() -> Set<UUID> {
        let refs = allCaptureRefs
        return Set(refs.map { $0.captureId })
    }

    // MARK: - Mutations

    private func commitChanges() {
        try? modelContext.save()
        changeCount += 1
    }

    func remove(_ item: WordItem) {
        modelContext.delete(item)
        commitChanges()
    }

    /// Remove a single word and trigger orphan cleanup for its capture images and thumbnails.
    func removeWithCleanup(_ item: WordItem, captureStore: CaptureStore, thumbnailStore: ThumbnailStore) {
        let captureIds = Set(item.captureRefs.map { $0.captureId })
        modelContext.delete(item)
        commitChanges()

        // Check which captures are still referenced
        let stillReferenced = allReferencedCaptureIds()
        let orphaned = captureIds.subtracting(stillReferenced)

        for id in orphaned {
            captureStore.delete(id: id)
            thumbnailStore.deleteAllForCapture(id)
        }
    }

    /// Batch-remove words with a single save and one orphan sweep.
    func removeWithCleanup(items: [WordItem], captureStore: CaptureStore, thumbnailStore: ThumbnailStore) {
        guard !items.isEmpty else { return }
        let removedCaptureIds = Set(items.flatMap(\.captureRefs).map(\.captureId))

        for item in items {
            modelContext.delete(item)
        }
        commitChanges()

        let stillReferenced = allReferencedCaptureIds()
        let orphaned = removedCaptureIds.subtracting(stillReferenced)

        for id in orphaned {
            captureStore.delete(id: id)
            thumbnailStore.deleteAllForCapture(id)
        }
    }

    func remove(language: Language, lemma: String) {
        guard let existing = item(language: language, lemma: lemma) else { return }
        remove(existing)
    }

    /// Record candidates as vocabulary items.
    /// Image persistence (CaptureStore, ThumbnailStore) is the caller's responsibility.
    @discardableResult
    func record(
        _ candidates: [ScanCandidate],
        captureId: UUID,
        location: CapturedLocation? = nil
    ) -> [ScanCandidate] {
        guard !candidates.isEmpty else { return [] }

        let now = Date.now

        for candidate in candidates {
            let lemma = candidate.lemma.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lemma.isEmpty else { continue }

            let refBounds = candidate.bounds ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            let ref = CaptureReference(
                captureId: captureId,
                bounds: refBounds,
                capturedAt: now,
                location: location
            )

            if let existing = item(language: candidate.language, lemma: lemma) {
                existing.occurrences += 1
                existing.lastSeen = now
                if existing.translation == nil { existing.translation = candidate.translation }
                existing.sources.insert(candidate.source)
                existing.captureRefs.append(ref)
            } else {
                let newItem = WordItem(
                    language: candidate.language,
                    lemma: lemma,
                    translation: candidate.translation,
                    sources: [candidate.source],
                    occurrences: 1,
                    firstSeen: now,
                    lastSeen: now
                )
                modelContext.insert(newItem)
                newItem.captureRefs.append(ref)
            }
        }

        commitChanges()
        return candidates
    }

    // MARK: - Import

    /// Import a single portable word item with immediate save.
    /// Prefer `importItems(_:)` for batch imports.
    func importItem(_ portable: PortableWordItem) {
        mergeImportedItem(portable)
        commitChanges()
    }

    /// Batch-import portable word items with a single save at the end.
    func importItems(_ portableItems: [PortableWordItem]) {
        for portable in portableItems {
            mergeImportedItem(portable)
        }
        commitChanges()
    }

    /// Merge or insert a portable word item without saving.
    private func mergeImportedItem(_ portable: PortableWordItem) {
        let lemma = portable.lemma.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lemma.isEmpty else { return }

        if let existing = item(language: portable.language, lemma: lemma) {
            // Merge into existing word
            existing.firstSeen = min(existing.firstSeen, portable.firstSeen)
            existing.lastSeen = max(existing.lastSeen, portable.lastSeen)
            existing.occurrences = max(existing.occurrences, portable.occurrences)
            existing.sources.formUnion(portable.sources)
            if existing.translation == nil { existing.translation = portable.translation }

            // Append capture refs that aren't already present (by captureId + bounds)
            let existingRefKeys = Set(existing.captureRefs.map { refKey($0) })
            for pr in portable.captureRefs {
                let key = portableRefKey(pr)
                if !existingRefKeys.contains(key) {
                    let ref = CaptureReference(
                        captureId: pr.captureId,
                        bounds: pr.bounds,
                        capturedAt: pr.capturedAt,
                        location: pr.location
                    )
                    existing.captureRefs.append(ref)
                }
            }
        } else {
            // Create new word with original dates
            let newItem = WordItem(
                language: portable.language,
                lemma: lemma,
                translation: portable.translation,
                sources: portable.sources,
                occurrences: portable.occurrences,
                firstSeen: portable.firstSeen,
                lastSeen: portable.lastSeen
            )
            modelContext.insert(newItem)

            for pr in portable.captureRefs {
                let ref = CaptureReference(
                    captureId: pr.captureId,
                    bounds: pr.bounds,
                    capturedAt: pr.capturedAt,
                    location: pr.location
                )
                newItem.captureRefs.append(ref)
            }
        }
    }

    private func refKey(_ ref: CaptureReference) -> String {
        "\(ref.captureId.uuidString)-\(ref.boundsX)-\(ref.boundsY)"
    }

    private func portableRefKey(_ pr: PortableCaptureReference) -> String {
        "\(pr.captureId.uuidString)-\(pr.bounds.origin.x)-\(pr.bounds.origin.y)"
    }
}

// MARK: - Sort Option

enum WordSortOption: String, CaseIterable, Identifiable {
    case dateAdded, pictures, alphabetic
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dateAdded: return "Date Added"
        case .pictures: return "Pictures"
        case .alphabetic: return "Alphabetic"
        }
    }

    var icon: String {
        switch self {
        case .dateAdded: return "calendar"
        case .pictures: return "photo.stack"
        case .alphabetic: return "textformat"
        }
    }
}
