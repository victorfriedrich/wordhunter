import UIKit

/// Abstracts the source that provides images to the scan system.
///
/// Conformers include:
/// - `CameraScanSource`: live camera via VisionKit DataScanner
/// - `DemoScanSource`: static image from asset catalog (for App Review / simulator)
@MainActor
protocol ScanSource: AnyObject {

    /// Capture the current image (a camera frame, or the demo image, etc.)
    func capturePhoto() async throws -> UIImage
}
