import Foundation
import CoreLocation

/// Captured location data for a scan
///  Exists because SwiftData `@Model` classes cannot persist nested structs directly
/// `CaptureReference` flattens these fields into individual properties for storage
///  and reconstructs this type via its computed `location` property..
struct CapturedLocation: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let timestamp: Date
}
