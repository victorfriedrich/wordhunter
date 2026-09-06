import SwiftUI
import UIKit

// MARK: - Gallery Item Model

@available(iOS 18, *)
struct GalleryItem: Identifiable {
    let id: String
    let word: String
    let translation: String?
    let captureRefs: [CaptureReference]

    // Preserved for backward compatibility with FilmstripScrubber
    var captureRef: CaptureReference? { captureRefs.first }

    init(from wordItem: WordItem) {
        self.id = "\(wordItem.id)"
        self.word = wordItem.lemma
        self.translation = wordItem.translation
        // Sort newest first
        self.captureRefs = wordItem.captureRefs.sorted { $0.capturedAt > $1.capturedAt }
    }

    // Keep old initializer signature just in case it's constructed manually somewhere
    init(id: String, word: String, translation: String?, captureRef: CaptureReference?) {
        self.id = id
        self.word = word
        self.translation = translation
        if let ref = captureRef {
            self.captureRefs = [ref]
        } else {
            self.captureRefs = []
        }
    }

    func captureRef(at index: Int) -> CaptureReference? {
        guard index >= 0 && index < captureRefs.count else { return nil }
        return captureRefs[index]
    }
}

// MARK: - Gallery Image Cache
//
// Per-instance cache owned by @StateObject in PolaroidDetailScreen.
// SwiftUI creates it on open, deallocates on close — no manual clearing needed.

@available(iOS 18, *)
@MainActor
final class GalleryImageCache: ObservableObject {

    private var fullResCache: [String: UIImage] = [:]
    private var thumbnailCache: [String: UIImage] = [:]
    private var loadingTasks: [String: Task<Void, Never>] = [:]

    private func cacheKey(for item: GalleryItem, captureIndex: Int) -> String? {
        item.captureRef(at: captureIndex)?.captureId.uuidString
    }

    // MARK: - Thumbnails (synchronous, memory-cache only)

    func getThumbnail(for item: GalleryItem, captureIndex: Int = 0) -> UIImage? {
        guard let key = cacheKey(for: item, captureIndex: captureIndex) else { return nil }
        if let cached = thumbnailCache[key] { return cached }
        guard let ref = item.captureRef(at: captureIndex) else { return nil }

        let diskKey = "gallery-thumb-\(ref.captureId)-\(ref.bounds.minX)"
        if let memCached = ThumbCache.shared.get(diskKey) {
            thumbnailCache[key] = memCached
            return memCached
        }

        return nil
    }

    // MARK: - Thumbnails (async, disk-backed)

    func getThumbnailAsync(for item: GalleryItem, captureIndex: Int = 0) async -> UIImage? {
        guard let key = cacheKey(for: item, captureIndex: captureIndex) else { return nil }
        if let cached = thumbnailCache[key] { return cached }
        guard let ref = item.captureRef(at: captureIndex) else { return nil }

        let diskKey = "gallery-thumb-\(ref.captureId)-\(ref.bounds.minX)"
        if let memCached = ThumbCache.shared.get(diskKey) {
            thumbnailCache[key] = memCached
            return memCached
        }

        if let diskThumb = await ThumbnailStore.shared.loadAsync(captureId: ref.captureId, bounds: ref.bounds) {
            ThumbCache.shared.set(diskThumb, forKey: diskKey)
            thumbnailCache[key] = diskThumb
            return diskThumb
        }

        return nil
    }

    // MARK: - Full-Res (async, progressive)

    func getFullRes(for item: GalleryItem, captureIndex: Int = 0) -> UIImage? {
        guard let key = cacheKey(for: item, captureIndex: captureIndex) else { return nil }
        return fullResCache[key]
    }

    func preloadFullRes(for item: GalleryItem, captureIndex: Int = 0, priority: TaskPriority = .userInitiated) {
        guard let key = cacheKey(for: item, captureIndex: captureIndex) else { return }
        guard fullResCache[key] == nil, loadingTasks[key] == nil else { return }
        guard let ref = item.captureRef(at: captureIndex) else { return }

        loadingTasks[key] = Task(priority: priority) { [weak self] in
            let image = await Self.loadFullResImage(captureId: ref.captureId)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.fullResCache[key] = image
                self?.loadingTasks.removeValue(forKey: key)
                self?.objectWillChange.send()
            }
        }
    }

    // MARK: - Windowed Preloading

    func preloadAround(index: Int, items: [GalleryItem]) {
        guard !items.isEmpty else { return }

        let i = max(0, min(items.count - 1, index))
        let window = 3

        // Cancel tasks outside the window
        var keepIds = Set<String>()
        let keepRange = max(0, i - window)...min(items.count - 1, i + window)
        for idx in keepRange {
            let item = items[idx]
            if idx == i {
                keepIds.formUnion(item.captureRefs.map { $0.captureId.uuidString })
            } else if let first = item.captureRefs.first {
                keepIds.insert(first.captureId.uuidString)
            }
        }
        
        for key in loadingTasks.keys where !keepIds.contains(key) {
            loadingTasks[key]?.cancel()
            loadingTasks.removeValue(forKey: key)
        }

        // Evict full-res images far from current position
        var evictKeepIds = Set<String>()
        let evictRange = max(0, i - window * 2)...min(items.count - 1, i + window * 2)
        for idx in evictRange {
            let item = items[idx]
            evictKeepIds.formUnion(item.captureRefs.map { $0.captureId.uuidString })
        }
        
        for key in fullResCache.keys where !evictKeepIds.contains(key) {
            fullResCache.removeValue(forKey: key)
        }

        // Preload with priority gradient (always preloads the 0th capture of words)
        preloadFullRes(for: items[i], captureIndex: 0, priority: .userInitiated)
        if i > 0 { preloadFullRes(for: items[i - 1], captureIndex: 0, priority: .high) }
        if i < items.count - 1 { preloadFullRes(for: items[i + 1], captureIndex: 0, priority: .high) }

        for offset in 2...window {
            if i - offset >= 0 { preloadFullRes(for: items[i - offset], captureIndex: 0, priority: .utility) }
            if i + offset < items.count { preloadFullRes(for: items[i + offset], captureIndex: 0, priority: .utility) }
        }
    }

    // MARK: - Disk I/O

    private static func loadFullResImage(captureId: UUID) async -> UIImage? {
        let url = CaptureStore.captureURL(for: captureId)

        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
    }

    deinit {
        for task in loadingTasks.values { task.cancel() }
    }
}
