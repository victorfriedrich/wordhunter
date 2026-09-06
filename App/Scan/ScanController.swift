import SwiftUI
import VisionKit
import Vision

@available(iOS 18.0, *)
@MainActor
@Observable
final class ScanController {
    // MARK: - Scanner State

    var isSupported: Bool = true
    var isScanning: Bool = false
    var isProcessing: Bool = false

    /// User-visible error message when scan fails.
    var scanError: String? = nil

    /// True when running in demo mode (static image instead of camera).
    var isDemoMode: Bool { source is DemoScanSource }

    // MARK: - Demo Scene (Observable)

    /// The id of the active demo scene. Tracked by @Observable so views
    /// that read `demoSceneId` or `demoImage` re-render on scene switch.
    private(set) var demoSceneId: String?

    /// The UIImage for the current demo scene — derived from demoSceneId.
    var demoImage: UIImage? {
        guard let scene = (source as? DemoScanSource)?.scene else { return nil }
        return UIImage(named: scene.imageAssetName)
    }

    // MARK: - Results

    var resultPresentation: ScanResultPresentation?
    var pendingUnlock: AchievementUnlock?

    private var pendingUnlockQueue: [AchievementUnlock] = []

    // MARK: - Source

    /// The active image source — camera or demo. Set at init and stable.
    private(set) var source: ScanSource

    /// Convenience: the camera source, or nil when in demo mode.
    var cameraSource: CameraScanSource? { source as? CameraScanSource }

    // MARK: - Tap-to-capture

    /// Toggles on each tap-to-capture for sensory feedback.
    /// PersistentCameraLayer observes this with `.sensoryFeedback(trigger:)`.
    var tapHapticTrigger: Bool = false

    /// Closure invoked when the user taps recognized text on the DataScanner.
    /// Set by AppShellView once environment dependencies are available.
    /// PersistentCameraLayer forwards DataScanner taps through this.
    /// @ObservationIgnored because closures aren't observable state — only
    /// `tapHapticTrigger` needs to drive view updates.
    @ObservationIgnored var onTapText: (() -> Void)?

    // MARK: - Internal

    private var capturedLocation: CapturedLocation?

    /// Cached pipeline — avoids reloading deranking weights on every scan.
    private var cachedPipeline: (pipeline: ScanPipeline, language: Language)?

    // MARK: - Init

    init() {
        #if targetEnvironment(simulator)
        let demo = DemoScanSource(scene: .apple)
        self.source = demo
        self.demoSceneId = demo.scene.id
        #else
        let camera = CameraScanSource()
        if CameraScanSource.isAvailable {
            self.source = camera
            self.demoSceneId = nil
        } else {
            let demo = DemoScanSource(scene: .apple)
            self.source = demo
            self.demoSceneId = demo.scene.id
        }
        #endif
    }

    /// For testing — inject a specific source.
    init(source: ScanSource) {
        self.source = source
        self.demoSceneId = (source as? DemoScanSource)?.scene.id
    }

    // MARK: - Lifecycle

    func start() {
        // TODO: `isSupported` is never updated after init. Unsupported hardware and
        // denied camera access currently fall back to demo mode in `init`; derive
        // this from a camera-permission check instead.
        isScanning = isSupported
    }

    func stop() {
        isScanning = false
    }

    func clearResults() {
        resultPresentation = nil
        capturedLocation = nil
    }

    func clearPendingUnlock() {
        if pendingUnlockQueue.isEmpty {
            pendingUnlock = nil
        } else {
            pendingUnlock = pendingUnlockQueue.removeFirst()
        }
    }

    // MARK: - Demo Scene Switching

    /// Switch the active demo scene. Only works in demo mode.
    /// Updates the tracked `demoSceneId` so views re-render.
    func switchDemoScene(to scene: DemoScene) {
        guard let demoSource = source as? DemoScanSource else { return }
        guard scene.id != demoSource.scene.id else { return }

        clearResults()
        demoSource.loadScene(scene)
        // This is the @Observable-tracked write that triggers SwiftUI updates
        demoSceneId = scene.id
    }

    // MARK: - Capture

    func capture(
        settings: AppSettings,
        deps: AppDependencies,
        locationService: LocationService
    ) {
        Task { @MainActor in
            await performScan(
                settings: settings,
                deps: deps,
                locationService: locationService
            )
        }
    }

    // MARK: - Save

    /// Saves selected words, generates thumbnails, and evaluates achievements.
    /// Now async so thumbnail generation completes before the caller navigates
    /// away — guaranteeing thumbnails exist when CollectionScreen loads.
    func saveSelectedWords(
        to store: WordStore,
        captureStore: CaptureStore,
        thumbnailStore: ThumbnailStore,
        achievements: AchievementEngine
    ) async {
        guard let presentation = resultPresentation else { return }

        let candidates = presentation.selectedCandidates
        guard !candidates.isEmpty else { return }

        // Trigger animation warmup immediately while we process files.
        // This prevents framerate drops when the achievement screen eventually appears.
        Anim.warmUp()

        ClassificationLogger.shared.log(
                captureId: presentation.captureId,
                rawClassifications: presentation.rawClassifications.map { (label: $0.label, confidence: $0.confidence) },
                selectedCandidates: candidates
            )

        captureStore.save(presentation.captureImage, id: presentation.captureId)

        // Await thumbnail generation so files exist before navigating to collection.
        let thumbImage = presentation.captureImage
        let thumbCaptureId = presentation.captureId
        for candidate in candidates {
            let bounds = candidate.bounds ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            await thumbnailStore.save(
                from: thumbImage,
                bounds: bounds,
                captureId: thumbCaptureId
            )
            // Pre-populate in-memory cache so CollectionScreen rows find it instantly
            // without waiting for an async disk read.
            if let thumb = thumbnailStore.load(captureId: thumbCaptureId, bounds: bounds) {
                let collKey = "coll-\(thumbCaptureId)-\(bounds.minX)"
                ThumbCache.shared.set(thumb, forKey: collKey)
                // Also warm the gallery-thumb key used by PolaroidDetailScreen
                let galleryKey = "gallery-thumb-\(thumbCaptureId)-\(bounds.minX)"
                ThumbCache.shared.set(thumb, forKey: galleryKey)
            }
        }

        store.record(
            candidates,
            captureId: presentation.captureId,
            location: capturedLocation
        )

        let unlocks = achievements.evaluate(
            candidates: candidates,
            captureId: presentation.captureId,
            captureImage: presentation.captureImage,
            location: capturedLocation
        )
        if let first = unlocks.first {
            pendingUnlock = first
            pendingUnlockQueue = Array(unlocks.dropFirst())
        }

        clearResults()
    }

    // MARK: - Core Scan Flow

    private func performScan(
        settings: AppSettings,
        deps: AppDependencies,
        locationService: LocationService
    ) async {
        guard !isProcessing else { return }

        isProcessing = true
        capturedLocation = locationService.captureLocation()

        guard let photo = await capturePhoto() else {
            isProcessing = false
            return
        }

        let captureId = UUID()
        let pipeline = resolvePipeline(settings: settings, deps: deps)

        let demoHits = (source as? DemoScanSource)?.mockClassificationHits ?? []

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.resultPresentation = .processing(captureId: captureId, captureImage: photo)
        }

        await Task.yield()

        // Run classification first for progressive display, then pass
        // the result into the full pipeline so classification isn't repeated.
        let classificationResult = await pipeline.processClassificationOnly(
            captureImage: photo,
            classificationOverrideHits: demoHits
        )

        if !classificationResult.candidates.isEmpty {
            let partialScanResult = ScanResult(
                captureId: captureId,
                captureImage: photo,
                classificationCandidates: classificationResult.candidates,
                ocrCandidates: [],
                unresolvedTokens: [],
                rawClassifications: classificationResult.rawHits
            )
            var partialPresentation = pipeline.buildPresentation(from: partialScanResult)
            partialPresentation.isProcessing = true
            self.resultPresentation = partialPresentation
        }

        // Now run full pipeline (OCR only — classification is reused)
        let fullResult = await pipeline.process(
            captureId: captureId,
            captureImage: photo,
            classificationOverrideHits: demoHits,
            precomputedClassification: classificationResult
        )

        var presentation = pipeline.buildPresentation(from: fullResult)
        isProcessing = false

        guard presentation.hasAnyResults else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.resultPresentation = nil
            }
            return
        }

        if settings.shouldShowContextualSuggestions {
            presentation.isContextLoading = true
        }
        self.resultPresentation = presentation

        if settings.shouldShowContextualSuggestions {
            let rankedCandidates = presentation.classificationSection?.candidates ?? []
            var seenOrigins = Set<String>()
            var topEnglishLabels: [String] = []
            for candidate in rankedCandidates {
                guard let origin = candidate.originLabel?.lowercased(),
                      !origin.isEmpty,
                      !seenOrigins.contains(origin) else { continue }
                seenOrigins.insert(origin)
                topEnglishLabels.append(origin)
                if topEnglishLabels.count >= 5 { break }
            }

            let existingLemmas = Set(
                (fullResult.classificationCandidates + fullResult.ocrCandidates)
                    .map { $0.lemma.lowercased() }
            )

            Task { @MainActor in
                await self.fetchContextualSuggestions(
                    labels: topEnglishLabels,
                    existingLemmas: existingLemmas,
                    language: settings.sourceLanguage,
                    pipeline: pipeline,
                    captureId: captureId
                )
            }
        }
    }

    // MARK: - Scan Helpers

    private func resolvePipeline(settings: AppSettings, deps: AppDependencies) -> ScanPipeline {
        if let cached = cachedPipeline, cached.language == settings.sourceLanguage {
            return cached.pipeline
        }
        let pipeline = ScanPipeline(settings: settings, deps: deps)
        cachedPipeline = (pipeline, settings.sourceLanguage)
        return pipeline
    }

    // MARK: - Contextual Suggestions (Apple Intelligence)

    private func fetchContextualSuggestions(
        labels: [String],
        existingLemmas: Set<String>,
        language: Language,
        pipeline: ScanPipeline,
        captureId: UUID
    ) async {
        guard !labels.isEmpty else {
            clearContextLoading(for: captureId)
            return
        }

        let existingLabels = Set(labels.map { $0.lowercased() })
        let suggestedWords = await ContextualWordService.suggestWords(
            fromLabels: labels,
            existingLabels: existingLabels,
            language: language
        )

        guard !suggestedWords.isEmpty,
              var p = resultPresentation,
              p.captureId == captureId else {
            clearContextLoading(for: captureId)
            return
        }

        let contextSection = pipeline.buildContextSection(
            fromTargetLanguageWords: suggestedWords,
            excluding: existingLemmas
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            p.contextSection = contextSection
            p.isContextLoading = false
            self.resultPresentation = p
        }
    }

    private func clearContextLoading(for captureId: UUID) {
        if var p = resultPresentation, p.captureId == captureId {
            p.isContextLoading = false
            self.resultPresentation = p
        }
    }

    private func capturePhoto() async -> UIImage? {
        do {
            let raw = try await source.capturePhoto()
            return raw.normalizedToUpOrientation()
        } catch {
            scanError = "Capture failed. Please try again."
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if scanError != nil { scanError = nil }
            }
            return nil
        }
    }
}

extension UIImage {
    func normalizedToUpOrientation() -> UIImage {
        if imageOrientation == .up { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
