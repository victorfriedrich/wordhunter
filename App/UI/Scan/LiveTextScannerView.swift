import SwiftUI
import VisionKit
import UIKit
import os

#if DEBUG
private let debugStartTime = CFAbsoluteTimeGetCurrent()
private func debugLog(_ label: String) {
    Log.boot.debug("[\(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - debugStartTime), privacy: .public)s] \(label, privacy: .public)")
}
#endif

/// Coordinator that manages DataScannerViewController and provides photo capture.
@available(iOS 16.0, *)
@MainActor
final class ScannerCoordinator: NSObject, DataScannerViewControllerDelegate, ObservableObject {
    weak var scannerVC: DataScannerViewController?

    var onTapText: ((RecognizedText) -> Void)?
    
    /// Track camera readiness for logging
    private(set) var isCameraReady = false
    
    #if DEBUG
    private var hasLoggedFirstFrame = false
    #endif

    enum CaptureError: Error {
        case scannerUnavailable
    }

    func capturePhoto() async throws -> UIImage {
        guard let scannerVC else { throw CaptureError.scannerUnavailable }
        return try await scannerVC.capturePhoto()
    }

    private func normalizeToView(_ rect: CGRect) -> CGRect? {
        guard let view = scannerVC?.view else { return nil }
        let s = view.bounds.size
        guard s.width > 0, s.height > 0 else { return nil }

        return CGRect(
            x: rect.minX / s.width,
            y: rect.minY / s.height,
            width: rect.width / s.width,
            height: rect.height / s.height
        )
    }

    // MARK: - DataScannerViewControllerDelegate
    
    func dataScannerDidZoom(_ dataScanner: DataScannerViewController) {
        // Not used but available
    }
    
    func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
        #if DEBUG
        Log.boot.error("[BOOT] +\(bootElapsed(), privacy: .public)ms — DataScanner unavailable: \(String(describing: error), privacy: .public)")
        #endif
        isCameraReady = false
        #if DEBUG
        debugLog("DataScanner became unavailable: \(error)")
        #endif
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        guard case .text(let t) = item else { return }
        let transcript = t.transcript
        let bounds = boundsToRect(t.bounds)
        guard let nb = normalizeToView(bounds) else { return }
        onTapText?(RecognizedText(transcript: transcript, normalizedBounds: nb))
    }

    func dataScanner(_ dataScanner: DataScannerViewController,
                     didAdd addedItems: [RecognizedItem],
                     allItems: [RecognizedItem]) {
        if !isCameraReady {
            isCameraReady = true
            #if DEBUG
            Log.boot.debug("[BOOT] +\(bootElapsed(), privacy: .public)ms — camera ready (first recognized items received, \(allItems.count, privacy: .public) items)")
            #endif
        }
        #if DEBUG
        if !hasLoggedFirstFrame {
            debugLog("CAMERA LIVE - first text recognized")
            hasLoggedFirstFrame = true
        }
        #endif
    }

    func dataScanner(_ dataScanner: DataScannerViewController,
                     didUpdate updatedItems: [RecognizedItem],
                     allItems: [RecognizedItem]) {
    }

    func dataScanner(_ dataScanner: DataScannerViewController,
                     didRemove removedItems: [RecognizedItem],
                     allItems: [RecognizedItem]) {
    }

    private func extractTexts(_ items: [RecognizedItem]) -> [RecognizedText] {
        items.compactMap { item -> RecognizedText? in
            guard case .text(let t) = item else { return nil }
            let transcript = t.transcript
            let bounds = boundsToRect(t.bounds)
            guard let nb = normalizeToView(bounds) else { return nil }
            return RecognizedText(transcript: transcript, normalizedBounds: nb)
        }
    }
    
    private func boundsToRect(_ bounds: RecognizedItem.Bounds) -> CGRect {
        let minX = min(bounds.topLeft.x, bounds.bottomLeft.x)
        let maxX = max(bounds.topRight.x, bounds.bottomRight.x)
        let minY = min(bounds.topLeft.y, bounds.topRight.y)
        let maxY = max(bounds.bottomLeft.y, bounds.bottomRight.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

@available(iOS 16.0, *)
@MainActor
struct LiveTextScannerView: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    let coordinator: ScannerCoordinator

    var qualityLevel: DataScannerViewController.QualityLevel = .balanced
    var recognizesMultipleItems: Bool = true
    var isHighlightingEnabled: Bool = true

    var onTapText: (RecognizedText) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        #if DEBUG
        Log.boot.debug("[BOOT] +\(bootElapsed(), privacy: .public)ms — LiveTextScannerView.makeUIViewController (DataScanner created)")
        #endif
        let vc = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: qualityLevel,
            recognizesMultipleItems: recognizesMultipleItems,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: false,
            isHighlightingEnabled: isHighlightingEnabled
        )
        
        vc.delegate = coordinator
        coordinator.scannerVC = vc
        coordinator.onTapText = onTapText
        
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        coordinator.onTapText = onTapText

        if isScanning {
            if !uiViewController.isScanning {
                #if DEBUG
                Log.boot.debug("[BOOT] +\(bootElapsed(), privacy: .public)ms — DataScanner.startScanning() called")
                #endif
                try? uiViewController.startScanning()
            }
        } else {
            if uiViewController.isScanning {
                #if DEBUG
                Log.boot.debug("[BOOT] +\(bootElapsed(), privacy: .public)ms — DataScanner.stopScanning() called")
                #endif
                uiViewController.stopScanning()
            }
        }
    }

    func makeCoordinator() -> Void { }
}
