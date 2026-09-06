import SwiftUI
import VisionKit

@available(iOS 18.0, *)
struct ScanScreen: View {
    var scan: ScanController
    var onWordsSaved: (() -> Void)? = nil

    @Environment(WordStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AppDependencies.self) private var deps
    @Environment(LocationService.self) private var locationService
    @Environment(AchievementEngine.self) private var achievements
    @Environment(CaptureStore.self) private var captureStore
    @Environment(ThumbnailStore.self) private var thumbnailStore
    @Environment(CategoryProgressStore.self) private var categoryProgressStore

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // No camera layer here — the single DataScanner lives in
            // PersistentCameraLayer (RootView). This view is a transparent
            // overlay so taps on recognized text pass through to the camera.
            Color.clear
                .ignoresSafeArea()

            // Demo scene picker — top-right, only in demo mode when no results showing
            if scan.isDemoMode && scan.resultPresentation == nil {
                DemoScenePickerView(scanController: scan)
                    .padding(.top, 8)
                    .padding(.trailing, 12)
                    .transition(.opacity)
            }

            if scan.resultPresentation != nil {
                ScanResultView(
                    presentation: Binding(
                        get: { scan.resultPresentation },
                        set: { scan.resultPresentation = $0 }
                    ),
                    onSave: {
                        let hadPendingUnlock = scan.pendingUnlock != nil
                        // Wrap in Task so we can await the async save
                        // (thumbnails must finish before navigating to collection)
                        Task { @MainActor in
                            await scan.saveSelectedWords(
                                to: store,
                                captureStore: captureStore,
                                thumbnailStore: thumbnailStore,
                                achievements: achievements
                            )
                            if !hadPendingUnlock && scan.pendingUnlock == nil {
                                onWordsSaved?()
                            }
                        }
                    }
                )
            }
        }
        .onAppear {
            locationService.startUpdatingIfAuthorized()
        }
        .onDisappear {
            locationService.stopUpdating()
        }
    }
}
