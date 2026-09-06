import UIKit

/// Shared in-memory cache for thumbnail images.
/// NSCache is thread-safe, so we use @unchecked Sendable.
final class ThumbCache: @unchecked Sendable {
    static let shared = ThumbCache()
    
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        // Fix #20: Align count and cost limits.
        // At @3x, 100pt thumbnails = 300×300×4 = 360KB each.
        // 120 items × 360KB ≈ 43MB, safely under 40MB cost limit.
        cache.countLimit = 120
        cache.totalCostLimit = 40 * 1024 * 1024 // ~40MB
    }
    
    func get(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }
    
    func set(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    func remove(_ key: String) {
        cache.removeObject(forKey: key as NSString)
    }
    
    func clearAll() {
        cache.removeAllObjects()
    }
}
