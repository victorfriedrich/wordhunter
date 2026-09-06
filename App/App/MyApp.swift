import SwiftUI
import SwiftData
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Status bar style override (UIKit bridge)

struct StatusBarStyleSetter: UIViewControllerRepresentable {
    let style: UIStatusBarStyle
    
    func makeUIViewController(context: Context) -> Controller {
        Controller(style: style)
    }
    
    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.style = style
        uiViewController.setNeedsStatusBarAppearanceUpdate()
    }
    
    final class Controller: UIViewController {
        var style: UIStatusBarStyle
        
        init(style: UIStatusBarStyle) {
            self.style = style
            super.init(nibName: nil, bundle: nil)
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override var preferredStatusBarStyle: UIStatusBarStyle { style }
    }
}

extension View {
    func statusBarStyle(_ style: UIStatusBarStyle) -> some View {
        overlay(StatusBarStyleSetter(style: style).frame(width: 0, height: 0))
    }
}

@available(iOS 18, *)
@main
struct MyApp: App {
    private let container: ModelContainer
    @State private var scanController = ScanController()
    @State private var appState: AppState
    
    init() {
            // Pre-create Application Support directory to prevent scary CoreData warnings on fresh installs
            if let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            }
            
            let schema = Schema([WordItem.self, CaptureReference.self, AchievementRecord.self])
            let config = ModelConfiguration("WordLens", schema: schema)
            let container = try! ModelContainer(for: schema, configurations: [config])
            self.container = container
            self._appState = State(wrappedValue: AppState(modelContext: container.mainContext))
        }
    
    var body: some Scene {
        WindowGroup {
            RootView(scanController: scanController, appState: appState)
                .modelContainer(container)
        }
    }
}

@available(iOS 18.0, *)
struct RootView: View {
    var scanController: ScanController
    var appState: AppState
    
    @State private var bootPhase: BootPhase = .splash
    
    // Capture user's intro choices until we can apply them
    @State private var introLanguage: Language?
    @State private var introPreload: Bool = false
    
    // Status bar adaptivity for demo scenes
    @State private var prefersLightStatusBar = false
    
    private var hasCompletedIntro: Bool {
        UserDefaults.standard.bool(forKey: "app.hasCompletedIntro")
    }
    
    var body: some View {
        ZStack {
            // Camera layer persists behind everything but only once we're in the app
            // (not during splash/intro — starting the camera triggers permission prompts)
            if appState.isReady && bootPhase == .app {
                PersistentCameraLayer(scanController: scanController)
            }
            
            switch bootPhase {
            case .splash:
                SplashScreen()
                    .transition(.opacity)
                    .zIndex(3)
                
            case .intro:
                IntroScreen { language, preload in
                    introLanguage = language
                    introPreload = preload
                    advanceFromIntro()
                }
                .transition(.opacity)
                .zIndex(2)
                
            case .loading:
                LoadingScreen(status: loadingStatus)
                    .transition(.opacity)
                    .zIndex(2)
                
            case .app:
                if let resolved = appState.resolved {
                    AppShellView(scan: scanController)
                        .environment(resolved.store)
                        .environment(resolved.settings)
                        .environment(resolved.dependencies)
                        .environment(resolved.locationService)
                        .environment(resolved.achievementEngine)
                        .environment(resolved.categoryProgressStore)
                        .environment(resolved.captureStore)
                        .environment(resolved.thumbnailStore)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: bootPhase)
        .preferredColorScheme(.light)
        .statusBarStyle(statusBarStyleForCurrentState)
        .onAppear {
            updateStatusBarPreferenceFromDemoImage()
        }
        .onChange(of: scanController.isDemoMode) { _, _ in
            updateStatusBarPreferenceFromDemoImage()
        }
        .onChange(of: scanController.demoSceneId) { _, _ in
            updateStatusBarPreferenceFromDemoImage()
        }
        .task {
            if hasCompletedIntro {
                await appState.initialize()
                scanController.start()
                bootPhase = .app
            } else {
                try? await Task.sleep(for: .milliseconds(400))
                bootPhase = .intro
                await appState.initialize()
            }
        }
    }
    
    private var statusBarStyleForCurrentState: UIStatusBarStyle {
        if scanController.isDemoMode && (bootPhase != .splash) {
            return prefersLightStatusBar ? .lightContent : .darkContent
        }
        return .darkContent
    }
    
    private var loadingStatus: String {
        if !appState.isReady { return "Preparing your collection…" }
        if introPreload { return "Loading preloaded collection…" }
        return "Almost ready…"
    }
    
    private func advanceFromIntro() {
        if appState.isReady && !introPreload {
            applySettings()
            UserDefaults.standard.set(true, forKey: "app.hasCompletedIntro")
            scanController.start()
            withAnimation(.easeInOut(duration: 0.35)) {
                bootPhase = .app
            }
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                bootPhase = .loading
            }
            Task {
                while !appState.isReady {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                
                applySettings()
                
                if introPreload {
                    guard let resolved = appState.resolved else { return }
                    await PreloadedDataImporter.importPreloadedData(
                        language: introLanguage ?? .spanish,
                        wordStore: resolved.store,
                        achievementEngine: resolved.achievementEngine,
                        settings: resolved.settings,
                        captureStore: resolved.captureStore,
                        thumbnailStore: resolved.thumbnailStore
                    )
                    resolved.categoryProgressStore.recomputeAllProgress()
                }
                
                UserDefaults.standard.set(true, forKey: "app.hasCompletedIntro")
                scanController.start()
                
                withAnimation(.easeInOut(duration: 0.35)) {
                    bootPhase = .app
                }
            }
        }
    }
    
    private func applySettings() {
        guard let resolved = appState.resolved else { return }
        if let language = introLanguage, resolved.settings.sourceLanguage != language {
            resolved.settings.sourceLanguage = language
            resolved.categoryProgressStore.handleLanguageChange()
        }
    }
    
    private func updateStatusBarPreferenceFromDemoImage() {
        guard scanController.isDemoMode, let img = scanController.demoImage else {
            prefersLightStatusBar = false
            return
        }
        prefersLightStatusBar = isImageDark(img)
    }
    
    private func isImageDark(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let ciImage = CIImage(cgImage: cgImage)
        
        let filter = CIFilter.areaAverage()
        filter.inputImage = ciImage
        filter.extent = ciImage.extent
        
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let output = filter.outputImage else { return false }
        
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        
        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0
        
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance < 0.60
    }
}

@available(iOS 18.0, *)
struct PersistentCameraLayer: View {
    var scanController: ScanController
    
    var body: some View {
        if let cameraSource = scanController.cameraSource {
            LiveTextScannerView(
                isScanning: Binding(
                    get: { scanController.isScanning },
                    set: { scanController.isScanning = $0 }
                ),
                coordinator: cameraSource.coordinator,
                onTapText: { _ in
                    scanController.onTapText?()
                }
            )
            .ignoresSafeArea()
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: scanController.tapHapticTrigger)
        } else if scanController.isDemoMode {
            DemoBackgroundView(scanController: scanController)
        } else {
            Color.black.ignoresSafeArea()
        }
    }
}

@available(iOS 18.0, *)
struct DemoBackgroundView: View {
    var scanController: ScanController
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if let image = scanController.demoImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .id(scanController.demoSceneId)
                        .transition(.opacity)
                } else {
                    Color.black
                }
                
                LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: scanController.demoSceneId)
    }
}

@available(iOS 18.0, *)
struct DemoScenePickerView: View {
    var scanController: ScanController
    
    private let thumbSize: CGFloat = 52
    private let selectedScale: CGFloat = 1.08
    private let cornerRadius: CGFloat = 10
    private let scenes = DemoScene.all
    
    var body: some View {
        let rowSize = thumbSize * selectedScale
        
        VStack(spacing: 10) {
            ForEach(scenes) { scene in
                let isSelected = scene.id == scanController.demoSceneId
                
                Button {
                    scanController.switchDemoScene(to: scene)
                } label: {
                    ZStack {
                        Image(scene.imageAssetName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: thumbSize, height: thumbSize)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .stroke(Color.white, lineWidth: isSelected ? 2.5 : 0)
                            )
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                            .scaleEffect(isSelected ? selectedScale : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: isSelected)
                    }
                    .frame(width: rowSize, height: rowSize)
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .zIndex(isSelected ? 1 : 0)
                .buttonStyle(NoHighlightButtonStyle())
            }
        }
    }
}

@available(iOS 18, *)
@MainActor
@Observable
final class AppState {
    private(set) var isReady = false
    private let modelContext: ModelContext
    
    private(set) var store: WordStore?
    private(set) var settings: AppSettings?
    private(set) var dependencies: AppDependencies?
    private(set) var locationService: LocationService?
    private(set) var achievementEngine: AchievementEngine?
    private(set) var categoryProgressStore: CategoryProgressStore?
    private(set) var captureStore: CaptureStore?
    private(set) var thumbnailStore: ThumbnailStore?
    
    struct Resolved {
        let store: WordStore
        let settings: AppSettings
        let dependencies: AppDependencies
        let locationService: LocationService
        let achievementEngine: AchievementEngine
        let categoryProgressStore: CategoryProgressStore
        let captureStore: CaptureStore
        let thumbnailStore: ThumbnailStore
    }
    
    var resolved: Resolved? {
        guard isReady,
              let store, let settings, let dependencies,
              let locationService, let achievementEngine,
              let categoryProgressStore, let captureStore, let thumbnailStore
        else { return nil }
        
        return Resolved(
            store: store,
            settings: settings,
            dependencies: dependencies,
            locationService: locationService,
            achievementEngine: achievementEngine,
            categoryProgressStore: categoryProgressStore,
            captureStore: captureStore,
            thumbnailStore: thumbnailStore
        )
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func initialize() async {
        guard !isReady else { return }
        
        // Fast Synchronous Class Initializations
        let dependencies = AppDependencies()
        let settings = AppSettings()
        let store = WordStore(modelContext: modelContext)
        let locationService = LocationService()
        let achievementEngine = AchievementEngine(modelContext: modelContext)
        let captureStore = CaptureStore()
        let thumbnailStore = ThumbnailStore.shared
        
        let categoryProgressStore = CategoryProgressStore(
            modelContext: modelContext,
            settings: settings,
            lexicon: dependencies.lexiconProvider.sqlite
        )
        
        // Run Heavy Operations Asynchronously
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await dependencies.lexiconProvider.sqlite?.prepareDatabase(assetName: "lexicon")
            }
            group.addTask {
                await categoryProgressStore.loadInitialData()
            }
        }
        
        self.store = store
        self.settings = settings
        self.dependencies = dependencies
        self.locationService = locationService
        self.achievementEngine = achievementEngine
        self.categoryProgressStore = categoryProgressStore
        self.captureStore = captureStore
        self.thumbnailStore = thumbnailStore
        
        isReady = true
    }
}
