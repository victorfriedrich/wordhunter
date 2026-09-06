import Foundation
import UIKit
import SwiftData

/// Evaluates achievements and maintains collection state.
@available(iOS 18, *)
@MainActor
@Observable
final class AchievementEngine {
    private let modelContext: ModelContext

    /// Tracked set of unlocked achievement IDs — drives view reactivity.
    /// Views that read `isUnlocked()`, `unlockedIds`, or `unlockedCount`
    /// will automatically re-render when this set changes.
    private var _unlockedIds: Set<AchievementId> = []

    /// Cached collection data, updated incrementally
    private var collectedLemmas: Set<String> = []

    /// Cached scan days for streak computation — updated incrementally
    private var cachedScanDays: Set<Date> = []

    /// Location permission - set externally
    var hasLocationPermission: Bool = false

    /// External references for richer context
    private var wordStore: WordStore?
    private var categoryProgressStore: CategoryProgressStore?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Load persisted unlocks into the tracked set
        let descriptor = FetchDescriptor<AchievementRecord>()
        let records = (try? modelContext.fetch(descriptor)) ?? []
        _unlockedIds = Set(records.compactMap { AchievementId(rawValue: $0.achievementId) })
    }

    // MARK: - Queries (all read from the tracked _unlockedIds)

    func isUnlocked(_ id: AchievementId) -> Bool {
        _unlockedIds.contains(id)
    }

    var unlockedIds: Set<AchievementId> {
        _unlockedIds
    }

    var unlockedCount: Int {
        _unlockedIds.count
    }

    var totalCount: Int { Achievements.all.count }

    /// Persist an unlock. Returns true only if the save succeeds,
    /// preventing divergence between in-memory and persisted state.
    @discardableResult
    private func unlock(_ id: AchievementId) -> Bool {
        guard !_unlockedIds.contains(id) else { return false }
        let record = AchievementRecord(achievementId: id)
        modelContext.insert(record)
        do {
            try modelContext.save()
            _unlockedIds.insert(id)
            return true
        } catch {
            modelContext.rollback()
            return false
        }
    }

    /// Call once on launch with existing words and stores.
    /// The expensive captureRefs traversal is done on a background thread
    /// to avoid blocking the main actor during startup.
    func initialize(
        words: [WordItem],
        wordStore: WordStore? = nil,
        categoryProgressStore: CategoryProgressStore? = nil
    ) {
        // Fast: just lemma strings, no relationship faulting
        collectedLemmas = Set(words.map { $0.lemma.lowercased() })
        self.wordStore = wordStore
        self.categoryProgressStore = categoryProgressStore

        // Slow: captureRefs triggers SwiftData relationship faults per item.
        // Move to background GCD thread to avoid blocking the main actor.
        // cachedScanDays is only needed for streak computation during evaluate(),
        // which happens on user tap — not at boot.
        let container = modelContext.container
        Task {
            await loadScanDaysInBackground(container: container)
        }
    }

    /// Loads scan days by fetching CaptureReference directly on a GCD background
    /// thread, avoiding the expensive WordItem → captureRefs relationship faulting.
    private func loadScanDaysInBackground(container: ModelContainer) async {
        let scanDays: Set<Date> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let bgContext = ModelContext(container)

                // FIX: Fetch CaptureReference.capturedAt directly instead of
                // going through WordItem.captureRefs which faults every relationship.
                var descriptor = FetchDescriptor<CaptureReference>()
                descriptor.propertiesToFetch = [\.capturedAt]
                let refs = (try? bgContext.fetch(descriptor)) ?? []

                let calendar = Calendar.current
                var days: Set<Date> = []
                for ref in refs {
                    days.insert(calendar.startOfDay(for: ref.capturedAt))
                }

                continuation.resume(returning: days)
            }
        }

        self.cachedScanDays = scanDays
    }

    /// Fix #11: Import achievements by unlocking them without re-evaluating checks.
    /// Called during data import to restore previously unlocked achievements.
    func importAchievements(_ ids: [AchievementId]) {
        for id in ids {
            unlock(id)
        }
    }

    /// Re-initialize collected lemmas after import (new words may have been added).
    func reinitializeAfterImport(words: [WordItem]) {
        collectedLemmas = Set(words.map { $0.lemma.lowercased() })
        let calendar = Calendar.current
        cachedScanDays.removeAll()
        for item in words {
            for ref in item.captureRefs {
                cachedScanDays.insert(calendar.startOfDay(for: ref.capturedAt))
            }
        }
    }

    /// Evaluate after save. Returns all unlocks (may be multiple per scan).
    func evaluate(
        candidates: [ScanCandidate],
        captureId: UUID,
        captureImage: UIImage,
        location: CapturedLocation?
    ) -> [AchievementUnlock] {

        for c in candidates {
            collectedLemmas.insert(c.lemma.lowercased())
        }

        let today = Calendar.current.startOfDay(for: .now)
        cachedScanDays.insert(today)

        // Fix: Refresh category progress *before* evaluating achievements,
        // so generalist/specialist checks see up-to-date data.
        categoryProgressStore?.recomputeAllProgress()

        let streak = computeConsecutiveScanDays()
        let catProgress = computeCategoryProgress()

        // Only compute word locations when Déjà Vu is still locked and location
        // permission is granted — avoids SwiftData fetches on every scan otherwise.
        let wordLocs: [String: [CapturedLocation]]
        if !_unlockedIds.contains(.dejaVu) && hasLocationPermission {
            wordLocs = computeWordLocations(for: candidates, currentLocation: location)
        } else {
            wordLocs = [:]
        }

        // Only pass allCollectedLemmas if an achievement that needs it is still locked.
        // alphabetSoup and theSumOfItsParts are the only consumers.
        let needsAllLemmas = !_unlockedIds.contains(.alphabetSoup)
            || !_unlockedIds.contains(.theSumOfItsParts)
        let lemmasForContext = needsAllLemmas ? collectedLemmas : []

        let context = ScanContext(
            candidates: candidates,
            captureId: captureId,
            timestamp: .now,
            location: location,
            totalWordCount: collectedLemmas.count,
            allCollectedLemmas: lemmasForContext,
            consecutiveScanDays: streak,
            categoryProgress: catProgress,
            wordLocations: wordLocs
        )

        var unlocks: [AchievementUnlock] = []
        for achievement in Achievements.all {
            guard !_unlockedIds.contains(achievement.id) else { continue }
            guard !achievement.requiresLocation || hasLocationPermission else { continue }

            if achievement.check(context) {
                if unlock(achievement.id) {
                    unlocks.append(AchievementUnlock(achievement: achievement, captureImage: captureImage))
                }
            }
        }

        return unlocks
    }

    // MARK: - Streak Computation

    private func computeConsecutiveScanDays() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        var streak = 0
        var checkDate = today
        while cachedScanDays.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        return streak
    }

    // MARK: - Category Progress

    private func computeCategoryProgress() -> [(collected: Int, total: Int)] {
        guard let store = categoryProgressStore else { return [] }
        return store.progress.map { (collected: $0.unlockedCount, total: $0.totalCount) }
    }

    // MARK: - Word Locations

    private func computeWordLocations(
        for candidates: [ScanCandidate],
        currentLocation: CapturedLocation?
    ) -> [String: [CapturedLocation]] {
        guard let wordStore else { return [:] }

        var result: [String: [CapturedLocation]] = [:]

        for candidate in candidates {
            let lemma = candidate.lemma.lowercased()
            guard result[lemma] == nil else { continue }

            var locations: [CapturedLocation] = []

            if let item = wordStore.item(language: candidate.language, lemma: candidate.lemma) {
                for ref in item.captureRefs {
                    if let loc = ref.location {
                        locations.append(loc)
                    }
                }
            }

            if let loc = currentLocation {
                locations.append(loc)
            }

            if locations.count >= 3 {
                result[lemma] = locations
            }
        }

        return result
    }
}
