import SwiftUI

@available(iOS 18.0, *)
struct AppShellView: View {
    @Environment(WordStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AppDependencies.self) private var deps
    @Environment(LocationService.self) private var locationService
    @Environment(AchievementEngine.self) private var achievements
    @Environment(CategoryProgressStore.self) private var categoryProgressStore
    @Environment(CaptureStore.self) private var captureStore
    @Environment(ThumbnailStore.self) private var thumbnailStore

    @State private var selectedTab: AppTab = .scan
    var scan: ScanController
    @State private var celebratingUnlock: AchievementUnlock?

    var body: some View {
        let content = GeometryReader { proxy in
            AppShellContent(
                proxy: proxy,
                selectedTab: $selectedTab,
                scan: scan,
                celebratingUnlock: $celebratingUnlock
            )
        }

        return content
            .onChange(of: selectedTab) { _, newTab in
                handleTabChange(newTab)
            }
            .onChange(of: scan.pendingUnlock?.achievement.id) { _, _ in
                handlePendingUnlock()
            }
            .onChange(of: settings.sourceLanguage) { _, _ in
                            categoryProgressStore.handleLanguageChange()
                            // Re-initialize achievements for the newly selected language
                            let words = store.allItems(for: settings.sourceLanguage)
                            achievements.initialize(words: words, wordStore: store, categoryProgressStore: categoryProgressStore)
                        }
            .onChange(of: locationService.isAuthorized) { _, newValue in
                achievements.hasLocationPermission = newValue
            }
            .task {
                initializeOnAppear()
            }
    }

    private func handleTabChange(_ newTab: AppTab) {
        if newTab == .scan {
            scan.start()
            locationService.requestAuthorizationIfNeeded()
            locationService.startUpdatingIfAuthorized()
        } else {
            Task { @MainActor in
                await Task.yield()
                scan.stop()
                locationService.stopUpdating()
                await Task.yield()
                scan.clearResults()
            }
        }
        if newTab == .categories {
            categoryProgressStore.recomputeAllProgress()
        }
    }

    private func handlePendingUnlock() {
        if let unlock = scan.pendingUnlock {
            withAnimation(.easeInOut(duration: 0.3)) {
                celebratingUnlock = unlock
            }
            scan.clearPendingUnlock()
        }
    }

    private func initializeOnAppear() {
        let words = store.allItems(for: settings.sourceLanguage)

        achievements.initialize(
            words: words,
            wordStore: store,
            categoryProgressStore: categoryProgressStore
        )

        achievements.hasLocationPermission = locationService.isAuthorized

        let capturedSettings = settings
        let capturedDeps = deps
        let capturedLocationService = locationService
        let popupSpring = Animation.spring(response: 0.33, dampingFraction: 0.58)
        scan.onTapText = { [scan] in
            scan.tapHapticTrigger.toggle()
            withAnimation(popupSpring) {
                scan.capture(
                    settings: capturedSettings,
                    deps: capturedDeps,
                    locationService: capturedLocationService
                )
            }
        }

        if selectedTab == .scan {
            locationService.requestAuthorizationIfNeeded()
            locationService.startUpdatingIfAuthorized()
        }
    }
}

@available(iOS 18.0, *)
private struct AppShellContent: View {
    let proxy: GeometryProxy
    @Binding var selectedTab: AppTab
    var scan: ScanController
    @Binding var celebratingUnlock: AchievementUnlock?

    @Environment(WordStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AppDependencies.self) private var deps
    @Environment(LocationService.self) private var locationService
    @Environment(AchievementEngine.self) private var achievements
    @Environment(CaptureStore.self) private var captureStore
    @Environment(ThumbnailStore.self) private var thumbnailStore

    private var bottomInset: CGFloat { proxy.safeAreaInsets.bottom }
    private var bottomOverlayPadding: CGFloat { 32 + bottomInset }

    // Track which tabs have been visited so we can lazily initialize them
    @State private var visitedTabs: Set<AppTab> = [.scan]

    var body: some View {
        ZStack {
            mainContent
                .opacity(celebratingUnlock == nil ? 1 : 0)
                .allowsHitTesting(celebratingUnlock == nil)

            if let unlock = celebratingUnlock {
                AchievementCelebrationView(
                    unlock: unlock,
                    bottomOverlayPadding: bottomOverlayPadding,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            celebratingUnlock = nil
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            selectedTab = .collection
                        }
                    }
                )
                .id(unlock.achievement.id)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            bottomBarOverlay
        }
        .onChange(of: selectedTab) { _, newTab in
            // Record that we've visited this tab so it stays alive
            visitedTabs.insert(newTab)
        }
    }

    private var mainContent: some View {
        ZStack {
            if selectedTab != .scan {
                Color.white
                    .ignoresSafeArea()
            }

            ScanScreen(
                scan: scan,
                onWordsSaved: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = .collection
                    }
                }
            )
                .opacity(selectedTab == .scan ? 1 : 0)
                .allowsHitTesting(selectedTab == .scan)

            if visitedTabs.contains(.achievements) {
                AchievementsScreen()
                    .opacity(selectedTab == .achievements ? 1 : 0)
                    .allowsHitTesting(selectedTab == .achievements)
            }

            if visitedTabs.contains(.collection) {
                CollectionScreen(bottomOverlayPadding: bottomOverlayPadding)
                    .opacity(selectedTab == .collection ? 1 : 0)
                    .allowsHitTesting(selectedTab == .collection)
            }

            if visitedTabs.contains(.categories) {
                CategoriesView(bottomOverlayPadding: bottomOverlayPadding)
                    .opacity(selectedTab == .categories ? 1 : 0)
                    .allowsHitTesting(selectedTab == .categories)
            }
        }
    }

    @ViewBuilder
    private var bottomBarOverlay: some View {
        if scan.resultPresentation == nil && celebratingUnlock == nil {
            BottomBarView(
                selectedTab: $selectedTab,
                bottomInset: bottomInset,
                showCapture: selectedTab == .scan,
                isCaptureEnabled: selectedTab == .scan && scan.isSupported && scan.isScanning && !scan.isProcessing,
                onCapture: {
                    withAnimation(.spring(response: 0.33, dampingFraction: 0.58)) {
                        scan.capture(settings: settings, deps: deps, locationService: locationService)
                    }
                }
            )
        }
    }
}

private struct AchievementCelebrationView: View {
    let unlock: AchievementUnlock
    let bottomOverlayPadding: CGFloat
    let onDismiss: () -> Void

    @State private var isAnimating = false

    private var achievementImage: UIImage {
        UIImage(named: unlock.achievement.imageName) ?? unlock.captureImage
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            AchievementUnlockScreen(
                isVisible: isAnimating,
                image: achievementImage,
                achievementName: unlock.achievement.name,
                achievementDescription: unlock.achievement.description,
                onContinue: onDismiss
            )
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isAnimating = true
            }
        }
    }
}

#if DEBUG
@available(iOS 18.0, *)
private struct DebugPracticeView: View {
    let bottomOverlayPadding: CGFloat
    let isActive: Bool

    @State private var isVisible: Bool = false
    @State private var viewKey = UUID()
    @State private var currentAchievement: Achievement = Achievements.all.randomElement()!

    var body: some View {
        ZStack {
            AchievementUnlockScreen(
                isVisible: isVisible,
                image: UIImage(named: currentAchievement.imageName) ?? UIImage(),
                achievementName: currentAchievement.name,
                achievementDescription: currentAchievement.description,
                onContinue: {
                    currentAchievement = Achievements.all.randomElement()!
                    isVisible = false
                    viewKey = UUID()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isVisible = true
                    }
                }
            )
            .id(viewKey)

            VStack {
                Spacer()
                Button("Replay Random") {
                    currentAchievement = Achievements.all.randomElement()!
                    isVisible = false
                    viewKey = UUID()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isVisible = true
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
                .padding(.bottom, bottomOverlayPadding + 80)
            }
        }
        .onChange(of: isActive) { _, active in
            isVisible = active
            if active { viewKey = UUID() }
        }
    }
}
#endif
