import UIKit

/// Stores and retrieves pre-generated thumbnails for saved words.
///
/// Thumbnails are generated once when a word is saved and stored as small JPEGs (~5-10KB each).
/// This eliminates the need to load full-size captures (12MP) when displaying collection/category lists.
///
/// File naming: `{captureId}_{boundsHash}.jpg`
/// Storage location: Documents/Thumbnails/
@available(iOS 18, *)
@MainActor
@Observable
final class ThumbnailStore {
    static let shared = ThumbnailStore()
    static let size: CGFloat = 100

    private let quality: CGFloat = 0.75

    init() {
        try? FileManager.default.createDirectory(at: CaptureStore.thumbnailsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Save

    /// Save a thumbnail cropped from the capture image (async, off main actor).
    /// The image is assumed to already be in `.up` orientation (normalized by ScanController).
    func save(from image: UIImage, bounds: CGRect, captureId: UUID) async {
        let scale = UIScreen.main.scale
        let q = quality
        let url = CaptureStore.thumbnailURL(captureId: captureId, bounds: bounds)
        let thumbSize = Self.size
        await Task.detached(priority: .userInitiated) {
            guard let thumbnail = generateThumbnail(from: image, bounds: bounds, scale: scale, size: thumbSize) else { return }
            if let data = thumbnail.jpegData(compressionQuality: q) {
                try? data.write(to: url, options: .atomic)
            }
        }.value
    }

    // MARK: - Load

    /// Synchronous load — use only when already off main or for cache-hit paths.
    func load(captureId: UUID, bounds: CGRect) -> UIImage? {
        let url = CaptureStore.thumbnailURL(captureId: captureId, bounds: bounds)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Async thumbnail load — performs disk I/O off the main actor.
    nonisolated func loadAsync(captureId: UUID, bounds: CGRect) async -> UIImage? {
        let url = await CaptureStore.thumbnailURL(captureId: captureId, bounds: bounds)
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
    }

    func exists(captureId: UUID, bounds: CGRect) -> Bool {
        FileManager.default.fileExists(atPath: CaptureStore.thumbnailURL(captureId: captureId, bounds: bounds).path)
    }

    // MARK: - Delete

    func delete(captureId: UUID, bounds: CGRect) {
        try? FileManager.default.removeItem(at: CaptureStore.thumbnailURL(captureId: captureId, bounds: bounds))
    }

    func deleteAllForCapture(_ captureId: UUID) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: CaptureStore.thumbnailsDirectory, includingPropertiesForKeys: nil) else { return }
        let prefix = captureId.uuidString
        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Migration

    func migrateIfNeeded(refs: [CaptureReference]) async -> Int {
        let missing = refs.filter { !exists(captureId: $0.captureId, bounds: $0.bounds) }
        guard !missing.isEmpty else { return 0 }

        let grouped = Dictionary(grouping: missing) { $0.captureId }
        var count = 0

        for (captureId, refs) in grouped {
            let url = CaptureStore.captureURL(for: captureId)
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { continue }

            for ref in refs {
                await save(from: image, bounds: ref.bounds, captureId: captureId)
                count += 1
            }
        }

        return count
    }
}

// MARK: - Thumbnail Generation (free function, not actor-isolated)

/// Generate a square thumbnail from a capture image.
/// Free function so it can be called from any isolation context (e.g. Task.detached).
private func generateThumbnail(from image: UIImage, bounds: CGRect, scale: CGFloat, size: CGFloat) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }

    let imgW = CGFloat(cgImage.width)
    let imgH = CGFloat(cgImage.height)

    let pixelBounds = CGRect(
        x: bounds.minX * imgW,
        y: bounds.minY * imgH,
        width: bounds.width * imgW,
        height: bounds.height * imgH
    )

    let padding: CGFloat = 90
    let side = max(pixelBounds.width, pixelBounds.height) + padding * 2
    var cropRect = CGRect(
        x: pixelBounds.midX - side / 2,
        y: pixelBounds.midY - side / 2,
        width: side,
        height: side
    )

    cropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
    guard !cropRect.isEmpty, let cropped = cgImage.cropping(to: cropRect) else { return nil }

    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = true

    let targetSize = CGSize(width: size, height: size)
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

    return renderer.image { ctx in
        UIColor.systemGray6.setFill()
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        let croppedImage = UIImage(cgImage: cropped)
        let sourceAspect = croppedImage.size.width / croppedImage.size.height
        let targetAspect = targetSize.width / targetSize.height

        let drawRect: CGRect
        if sourceAspect > targetAspect {
            let drawHeight = targetSize.height
            let drawWidth = drawHeight * sourceAspect
            let xOffset = (targetSize.width - drawWidth) / 2
            drawRect = CGRect(x: xOffset, y: 0, width: drawWidth, height: drawHeight)
        } else {
            let drawWidth = targetSize.width
            let drawHeight = drawWidth / sourceAspect
            let yOffset = (targetSize.height - drawHeight) / 2
            drawRect = CGRect(x: 0, y: yOffset, width: drawWidth, height: drawHeight)
        }

        croppedImage.draw(in: drawRect)
    }
}
