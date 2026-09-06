import UIKit

/// Stores capture images on disk, keyed by UUID.
/// One capture per scan, referenced by multiple words.
///
/// Also serves as the single source of truth for capture/thumbnail directory paths.
/// Other components should use the static URL helpers instead of hardcoding paths.
@available(iOS 17.0, *)
@MainActor
@Observable
final class CaptureStore {
    private let quality: CGFloat = 0.8

    // MARK: - Centralized Directory Paths

    /// Documents directory root.
    static let documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    /// Directory where full-resolution capture images are stored.
    static let capturesDirectory: URL = documentsDirectory.appendingPathComponent("Captures", isDirectory: true)

    /// Directory where pre-generated thumbnails are stored.
    static let thumbnailsDirectory: URL = documentsDirectory.appendingPathComponent("Thumbnails", isDirectory: true)

    /// URL for a specific capture image.
    static func captureURL(for captureId: UUID) -> URL {
        capturesDirectory.appendingPathComponent("\(captureId.uuidString).jpg")
    }

    /// URL for a specific thumbnail image.
    static func thumbnailURL(captureId: UUID, bounds: CGRect) -> URL {
        let bx = Int(bounds.minX * 10000)
        let by = Int(bounds.minY * 10000)
        let bw = Int(bounds.width * 10000)
        let bh = Int(bounds.height * 10000)
        let filename = "\(captureId.uuidString)_\(bx)_\(by)_\(bw)_\(bh).jpg"
        return thumbnailsDirectory.appendingPathComponent(filename)
    }

    // MARK: - Init

    init() {
        try? FileManager.default.createDirectory(at: Self.capturesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - CRUD

    func save(_ image: UIImage, id: UUID) {
        let url = Self.captureURL(for: id)
        guard let data = image.jpegData(compressionQuality: quality) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func load(id: UUID) -> UIImage? {
        let url = Self.captureURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: Self.captureURL(for: id))
    }

    func exists(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: Self.captureURL(for: id).path)
    }
}
