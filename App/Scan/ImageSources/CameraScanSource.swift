import UIKit
import VisionKit

/// Wraps the live camera (VisionKit DataScanner) as a `ScanSource`.
@available(iOS 16.0, *)
@MainActor
final class CameraScanSource: ScanSource {
    let coordinator = ScannerCoordinator()

    /// Whether the device hardware and camera permission support live scanning.
    /// Used by `ScanController` to decide whether to fall back to demo mode.
    /// TODO: This should be handled differently
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func capturePhoto() async throws -> UIImage {
        try await coordinator.capturePhoto()
    }
}
