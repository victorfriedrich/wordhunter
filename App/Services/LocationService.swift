import Foundation
import CoreLocation

/// Manages location updates for capture enrichment.
///
/// Location is optional: captures work without it, but two achievements
/// ("Above the Clouds", "Déjà Vu") need it, so the app asks for When In Use
/// authorization the first time the scanner becomes visible.
@available(iOS 17.0, *)
@MainActor
@Observable
final class LocationService: NSObject {
    // MARK: - State

    private(set) var isAuthorized: Bool = false
    private(set) var currentLocation: CapturedLocation?

    // MARK: - Private

    private let manager: CLLocationManager

    /// Whether the app *wants* updates (the Scan tab is visible), tracked
    /// separately from `isUpdating` so that granting permission mid-session
    /// starts updates immediately instead of waiting for the next tab change.
    private var wantsUpdates: Bool = false

    /// Whether CoreLocation is actually delivering updates right now.
    private var isUpdating: Bool = false

    // MARK: - Init

    override init() {
        manager = CLLocationManager()
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10

        updateAuthorizationStatus(manager.authorizationStatus)
    }

    // MARK: - Public API

    /// Asks for When In Use authorization, but only while the user has not yet
    /// answered. iOS ignores repeat requests once a choice is made, so this
    /// guard keeps the intent explicit rather than relying on that behaviour.
    func requestAuthorizationIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingIfAuthorized() {
        wantsUpdates = true
        guard isAuthorized, !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        wantsUpdates = false
        pauseUpdates()
    }

    func captureLocation() -> CapturedLocation? {
        guard let location = currentLocation,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 100 else {
            return nil
        }
        return location
    }

    // MARK: - Private

    /// Stops delivery without clearing `wantsUpdates`, so updates resume on
    /// their own if authorization comes back (e.g. changed in Settings).
    private func pauseUpdates() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    private func updateAuthorizationStatus(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            isAuthorized = true
        case .notDetermined, .restricted, .denied:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }
}

// MARK: - CLLocationManagerDelegate

@available(iOS 17.0, *)
extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            updateAuthorizationStatus(status)

            if isAuthorized {
                // Resume only if the Scan tab still wants updates.
                if wantsUpdates { startUpdatingIfAuthorized() }
            } else {
                pauseUpdates()
                currentLocation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        let captured = CapturedLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            timestamp: location.timestamp
        )

        Task { @MainActor in
            currentLocation = captured
        }
    }

    // CoreLocation calls this when a location update fails
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location unavailable — currentLocation stays nil or stale
    }
}
