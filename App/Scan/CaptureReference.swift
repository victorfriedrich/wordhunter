import Foundation
import SwiftData

@available(iOS 18, *)
@Model
final class CaptureReference {
    var captureId: UUID
    var boundsX: Double
    var boundsY: Double
    var boundsWidth: Double
    var boundsHeight: Double
    var capturedAt: Date
    var locationLatitude: Double?
    var locationLongitude: Double?
    var locationAltitude: Double?
    var locationHAccuracy: Double?
    var locationVAccuracy: Double?
    var locationTimestamp: Date?

    var word: WordItem?

    var bounds: CGRect {
        CGRect(x: boundsX, y: boundsY, width: boundsWidth, height: boundsHeight)
    }

    var location: CapturedLocation? {
        guard let lat = locationLatitude,
              let lon = locationLongitude,
              let alt = locationAltitude,
              let hAcc = locationHAccuracy,
              let vAcc = locationVAccuracy,
              let ts = locationTimestamp else { return nil }
        return CapturedLocation(
            latitude: lat, longitude: lon, altitude: alt,
            horizontalAccuracy: hAcc, verticalAccuracy: vAcc, timestamp: ts
        )
    }

    init(
        captureId: UUID,
        bounds: CGRect,
        capturedAt: Date = .now,
        location: CapturedLocation? = nil
    ) {
        self.captureId = captureId
        self.boundsX = bounds.origin.x
        self.boundsY = bounds.origin.y
        self.boundsWidth = bounds.width
        self.boundsHeight = bounds.height
        self.capturedAt = capturedAt
        self.locationLatitude = location?.latitude
        self.locationLongitude = location?.longitude
        self.locationAltitude = location?.altitude
        self.locationHAccuracy = location?.horizontalAccuracy
        self.locationVAccuracy = location?.verticalAccuracy
        self.locationTimestamp = location?.timestamp
    }
}
