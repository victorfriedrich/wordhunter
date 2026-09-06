import SwiftUI
import UIKit
import AVFoundation
import CoreHaptics
import os

// MARK: - Effect Player (audio + haptics), tuned for sync and no music ducking

@MainActor
final class EffectPlayer: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private var hapticEngine: CHHapticEngine?
    private var cachedPattern: CHHapticPattern?

    private let soundAssetName = "sound"
    private let hapticsAssetName = "haptics"

    init() {
        prepareAudioSession()
        prepareAudio()
        prepareHaptics()
    }

    // Do NOT duck other audio. Keep ambient music at normal volume.
    private func prepareAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .ambient respects silent switch, mixes with other audio.
            // If you want to ignore silent switch, use .playback + [.mixWithOthers]
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])

            // Optional: try to reduce latency a bit. Not guaranteed.
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.005)

            try session.setActive(true)
        } catch {
            Log.achievements.error("Audio session setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func prepareAudio() {
        guard let asset = NSDataAsset(name: soundAssetName) else { return }

        do {
            audioPlayer = try AVAudioPlayer(data: asset.data)
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()

            // Warm up first render path to reduce first play latency.
            if let p = audioPlayer {
                let oldVol = p.volume
                p.volume = 0
                p.currentTime = 0
                p.play()
                p.stop()
                p.currentTime = 0
                p.volume = oldVol
            }
        } catch {
            Log.achievements.error("Audio player init failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()

            if let asset = NSDataAsset(name: hapticsAssetName) {
                if let dict = try JSONSerialization.jsonObject(with: asset.data) as? [CHHapticPattern.Key: Any] {
                    cachedPattern = try CHHapticPattern(dictionary: dict)
                }
            }
        } catch {
            Log.achievements.error("Haptic engine failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Starts audio and haptics with independent delays.
    /// Use this to align "success" to the color explosion and clicks to compression.
    func playEffects(audioDelay: TimeInterval = 0, hapticsDelay: TimeInterval = 0) {
        // Audio
        if let p = audioPlayer {
            p.currentTime = 0
            if audioDelay <= 0 {
                p.play()
            } else {
                p.play(atTime: p.deviceCurrentTime + audioDelay)
            }
        }

        // Haptics
        if let engine = hapticEngine, let pattern = cachedPattern {
            do {
                let player = try engine.makePlayer(with: pattern)
                let when = engine.currentTime + max(0, hapticsDelay)
                try player.start(atTime: when)
            } catch {
                Log.achievements.error("Haptic playback failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Main Screen

struct AchievementUnlockScreen: View {
    let isVisible: Bool
    let image: UIImage
    let achievementName: String
    let achievementDescription: String
    var onContinue: (() -> Void)? = nil

    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var preparedImage: UIImage?
    @State private var t: Double = 0
    @State private var animationTask: Task<Void, Never>?
    @State private var isPreWarmed = false
    @StateObject private var effectPlayer = EffectPlayer()
    @State private var showContinueButton = false

    @AccessibilityFocusState private var focusedElement: FocusTarget?

    fileprivate enum FocusTarget: Hashable {
        case announcement
        case continueButton
    }

    // Sync tuning:
    // Your WAV "success" begins about 38 ms after the visual explosion at t == 1.7.
    // Easiest fix: start audio/haptics slightly before starting the animation.
    private let animationStartDelaySeconds: TimeInterval = 0.038

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if !isPreWarmed {
                AchievementCard(image: image, name: achievementName, desc: achievementDescription, size: 240, t: 0)
                    .opacity(0.01)
                    .onAppear { isPreWarmed = true }
                    .accessibilityHidden(true)
            }

            if isVisible {
                AchievementCard(
                    image: preparedImage ?? image,
                    name: achievementName,
                    desc: achievementDescription,
                    size: 240,
                    t: reduceMotion ? 3.6 : t
                )
                .id("card_\(achievementName)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Achievement unlocked. \(achievementName). \(achievementDescription)"))
                .accessibilityAddTraits(.isStaticText)
                .accessibilityHint(Text("Swipe right to find the Continue button."))
                .accessibilityFocused($focusedElement, equals: .announcement)
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilitySortPriority(2)
        .safeAreaInset(edge: .bottom) {
            if let onContinue, showContinueButton {
                Button(action: onContinue) {
                    Text("CONTINUE")
                }
                .buttonStyle(ContinueButtonStyle(
                    color: Color(.systemGray5),
                    depthColor: Color(.systemGray4)
                ))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel(Text("Continue"))
                .accessibilityHint(Text("Closes the achievement screen."))
                .accessibilityAddTraits(.isButton)
                .accessibilityFocused($focusedElement, equals: .continueButton)
                .accessibilitySortPriority(3)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showContinueButton)
        .task(id: isVisible) {
            if isVisible {
                startSequence()
            } else {
                stopAnimation()
            }
        }
    }

    private func startSequence() {
        t = 0
        showContinueButton = false
        Anim.warmUp()

        if voiceOverEnabled {
            focusedElement = .announcement
        }

        // Cancel any previous run and reset visuals, BEFORE starting a new task
        animationTask?.cancel()
        animationTask = nil

        var tx = Transaction()
        tx.animation = nil
        withTransaction(tx) { t = 0 }

        animationTask = Task { @MainActor in
            if preparedImage == nil {
                preparedImage = await ImagePreparer.preparePixelPerfect(image, size: 240, scale: scale)
            }
            guard !Task.isCancelled else { return }

            // Start effects first, then start the animation a tiny bit later
            if !reduceMotion {
                effectPlayer.playEffects(audioDelay: 0, hapticsDelay: 0)
            }

            if animationStartDelaySeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(animationStartDelaySeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }

            withAnimation(.linear(duration: 3.6)) {
                t = 3.6
            }

            try? await Task.sleep(nanoseconds: 3_400_000_000)
            guard !Task.isCancelled else { return }

            showContinueButton = true

            if voiceOverEnabled {
                focusedElement = .continueButton
            }
        }
    }

    private func stopAnimation(keepPreparedImage: Bool = false) {
        animationTask?.cancel()
        animationTask = nil
        showContinueButton = false

        var tx = Transaction()
        tx.animation = nil
        withTransaction(tx) { t = 0 }

        if !keepPreparedImage {
            preparedImage = nil
        }
    }
}

// MARK: - Continue Button Style

private struct ContinueButtonStyle: ButtonStyle {
    let color: Color
    let depthColor: Color

    func makeBody(configuration: Configuration) -> some View {
        // We let the Text dictate the button size, instead of wrapping it in an overlay.
        // This prevents the text from clipping if the user increases system font size.
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.black.opacity(0.6))
            .multilineTextAlignment(.center)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(depthColor)
                        .offset(y: 4)

                    RoundedRectangle(cornerRadius: 16)
                        .fill(color)
                        .offset(y: configuration.isPressed ? 4 : 0)
                }
            )
            .offset(y: configuration.isPressed ? 4 : 0)
            .contentShape(Rectangle())
    }
}

// MARK: - Visual Engine Logic

private struct AchievementCard: View, Animatable {
    let image: UIImage
    let name: String
    let desc: String
    let size: CGFloat
    var t: Double

    nonisolated var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    var body: some View {
        let d = Derived(t: t, size: size)

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text("Achievement Unlocked")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(d.preLabelTracking)
                .foregroundStyle(.black.opacity(0.45))
                .opacity(d.preLabelOpacity)
                // 1. Force it to stay on one line
                .lineLimit(1)
                // 2. Allow it to shrink down if it gets squeezed
                .minimumScaleFactor(0.6)
                // 3. Cap the maximum dynamic type size to prevent it from getting absurdly tall
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .padding(.bottom, 24)

            ZStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white)

                    Image(uiImage: image)
                        .resizable()
                        .frame(width: size, height: size)
                        .grayscale(1.0)
                        .brightness(d.brightness)
                        .contrast(d.contrast)
                        .opacity(d.grayOp)
                        .scaleEffect(d.grayScale)
                        .offset(y: d.grayOffY)

                    if t >= 1.7 {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: size, height: size)
                            .mask(Circle().frame(width: d.maskDim, height: d.maskDim))
                    }

                    Group {
                        if d.glowOp > 0.01 {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [.white, .white.opacity(0.7), .clear],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: max(1, d.glowSize / 2)
                                    )
                                )
                                .frame(width: d.glowSize, height: d.glowSize)
                                .opacity(d.glowOp)
                                .blur(radius: d.glowBlur)
                        }

                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white.opacity(0.9), lineWidth: 20)
                            .blur(radius: 35)
                            .opacity(d.rimOp)
                    }

                    if t >= 1.7 && d.flashOp > 0.01 {
                        FlashOverlay(dim: d.flashDim, op: d.flashOp, sOp: d.flashSOp, sRad: d.flashSRad)
                    }

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.8), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: d.shineW, height: size)
                        .opacity(d.shineOp)
                        .projectionEffect(
                            ProjectionTransform(
                                CGAffineTransform(
                                    a: 1,
                                    b: 0,
                                    c: CGFloat(tan(-20.0 * .pi / 180.0)),
                                    d: 1,
                                    tx: 0,
                                    ty: 0
                                )
                            )
                        )
                        .offset(x: d.shineOffX)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .drawingGroup()
                .shadow(color: .black.opacity(d.shOp), radius: d.shRad, y: d.shY)
                .shadow(color: .white.opacity(d.wGlow), radius: 50)
                .scaleEffect(d.releaseS)
            }
            .scaleEffect(d.pulse)

            VStack(spacing: 0) {
                Text(name)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Color(white: 0.1))
                    .opacity(d.nameOp)
                    .scaleEffect(d.nameS)
                    .offset(y: d.nameOffY)
                    .padding(.top, 24)
                    .fixedSize(horizontal: false, vertical: true)

                Text(desc)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.black.opacity(0.5))
                    .opacity(d.descOp)
                    .offset(y: d.descOffY)
                    .padding(.top, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(32)
    }
}

private struct FlashOverlay: View {
    let dim: CGFloat
    let op: CGFloat
    let sOp: CGFloat
    let sRad: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, .white.opacity(0.95), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(1, dim / 2)
                    )
                )
                .blendMode(.screen)

            Circle()
                .stroke(.black.opacity(sOp), lineWidth: 2)
                .blur(radius: sRad)
        }
        .frame(width: dim, height: dim)
        .opacity(op)
    }
}

private struct Derived {
    let preLabelOpacity: CGFloat
    let preLabelTracking: CGFloat
    let grayOp: CGFloat
    let grayOffY: CGFloat
    let grayScale: CGFloat
    let brightness: CGFloat
    let contrast: CGFloat
    let pulse: CGFloat
    let maskDim: CGFloat
    let releaseS: CGFloat
    let glowOp: CGFloat
    let glowSize: CGFloat
    let glowBlur: CGFloat
    let rimOp: CGFloat
    let flashDim: CGFloat
    let flashOp: CGFloat
    let flashSOp: CGFloat
    let flashSRad: CGFloat
    let shineW: CGFloat
    let shineOp: CGFloat
    let shineOffX: CGFloat
    let shY: CGFloat
    let shRad: CGFloat
    let shOp: CGFloat
    let wGlow: CGFloat
    let nameOp: CGFloat
    let nameS: CGFloat
    let nameOffY: CGFloat
    let descOp: CGFloat
    let descOffY: CGFloat

    init(t: Double, size: CGFloat) {
        func p(_ d: Double, _ dur: Double) -> Double { min(max((t - d) / dur, 0), 1) }
        func e(_ u: Double, _ c: Anim.Curve) -> Double { Anim.ease(u, c) }
        func l(_ a: Double, _ b: Double, _ u: Double) -> CGFloat { CGFloat(a + (b - a) * u) }

        preLabelOpacity = l(0, 1, e(p(0, 0.6), .standard))
        preLabelTracking = l(6.75, 4.05, e(p(0, 0.6), .standard))

        let gE = e(p(0, 0.6), .standard)
        grayOp = l(0, 1, gE)
        grayOffY = l(15, 0, gE)
        grayScale = l(0.95, 1, gE)

        brightness = CGFloat(Anim.kf(t, 0.6, 1.1, [(0, 1), (0.5, 1.1), (0.85, 1.25), (1, 1.4)], .material) - 1.0)
        contrast = CGFloat(Anim.kf(t, 0.6, 1.1, [(0, 1), (0.5, 1.05), (0.85, 1.1), (1, 1.12)], .material))

        pulse = l(1, 0.975, e(p(0.9, 0.8), .pulse))

        maskDim = t < 1.7 ? 0 : l(0, 1.6, e(p(1.7, 0.5), .releaseMask)) * size
        releaseS = l(0.975, 1, e(p(1.7, 0.6), .release))

        glowOp = t < 0.8 ? 0 : l(0, 0.85, e(p(0.8, 0.9), .material)) * (1 - l(0, 1, e(p(1.7, 0.2), .fade)))
        glowSize = l(0.3, 1, e(p(0.8, 0.9), .material)) * size
        glowBlur = l(20, 35, e(p(0.8, 0.9), .material))

        rimOp = l(0, 1, e(p(1.1, 0.6), .material)) * (1 - l(0, 1, e(p(1.7, 0.25), .fade)))

        flashDim = l(0.8, 2.8, e(p(1.7, 0.5), .flash)) * size
        flashOp = t < 1.7 ? 0 : l(1, 0, e(p(1.7, 0.5), .flash))
        flashSOp = l(0.12, 0, e(p(1.7, 0.5), .flash))
        flashSRad = l(40, 60, e(p(1.7, 0.5), .flash))

        shineW = size * 0.7
        shineOp = t < 2.3 ? 0 : l(0, 1, e(p(2.3, 0.5), .standard))
        shineOffX = l(-1.5 * Double(size), 1.5 * Double(size), e(p(2.3, 0.5), .standard))

        shY = l(12, 15, e(p(2, 0.8), .standard))
        shRad = l(40, 50, e(p(2, 0.8), .standard))
        shOp = l(0.12, 0.15, e(p(2, 0.8), .standard))
        wGlow = l(0.5, 0, e(p(2, 0.8), .standard))

        nameOp = t < 1.7 ? 0 : l(0, 1, e(p(1.7, 0.65), .release))
        nameS = l(0.85, 1, e(p(1.7, 0.65), .release))
        nameOffY = l(20, 0, e(p(1.7, 0.65), .release))

        descOp = t < 2.8 ? 0 : l(0, 1, e(p(2.8, 0.6), .standard))
        descOffY = l(12, 0, e(p(2.8, 0.6), .standard))
    }
}

enum Anim {
    
    enum Curve { case standard, material, pulse, releaseMask, release, flash, fade }

    static func ease(_ u: Double, _ c: Curve) -> Double { LUTs[c]!.y(u) }

    static func kf(_ t: Double, _ d: Double, _ dur: Double, _ f: [(Double, Double)], _ c: Curve) -> Double {
        let p = min(max((t - d) / dur, 0), 1)
        guard let first = f.first, let last = f.last else { return 0 }
        if p <= first.0 { return first.1 }
        if p >= last.0 { return last.1 }
        for i in 0..<(f.count - 1) {
            let (t0, v0) = f[i], (t1, v1) = f[i + 1]
            if p >= t0 && p <= t1 { return v0 + (v1 - v0) * ease((p - t0) / (t1 - t0), c) }
        }
        return last.1
    }

    static func warmUp() { _ = LUTs }

    private struct LUT {
        let xs: [Double]
        let ys: [Double]
        func y(_ x: Double) -> Double {
            let x = min(max(x, 0), 1)
            var lo = 0, hi = xs.count - 1
            while hi - lo > 1 {
                let m = (lo + hi) >> 1
                if xs[m] < x { lo = m } else { hi = m }
            }
            return ys[lo] + (ys[hi] - ys[lo]) * ((x - xs[lo]) / max(1e-5, xs[hi] - xs[lo]))
        }
    }

    private static let LUTs: [Curve: LUT] = {
        func c(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> LUT {
            var xs = [Double](), ys = [Double]()
            for i in 0...256 {
                let t = Double(i) / 256, mt = 1 - t
                xs.append(3 * mt * mt * t * x1 + 3 * mt * t * t * x2 + t * t * t)
                ys.append(3 * mt * mt * t * y1 + 3 * mt * t * t * y2 + t * t * t)
            }
            return LUT(xs: xs, ys: ys)
        }

        return [
            .standard: c(0.25, 0.46, 0.45, 0.94),
            .material: c(0.4, 0, 0.2, 1),
            .pulse: c(0.4, 0, 0.6, 1),
            .releaseMask: c(0.34, 1.2, 0.64, 1),
            .release: c(0.34, 1.56, 0.64, 1),
            .flash: c(0.16, 1, 0.3, 1),
            .fade: c(0.4, 0, 1, 1)
        ]
    }()
}

enum ImagePreparer {
    static func preparePixelPerfect(_ img: UIImage, size: CGFloat, scale: CGFloat) async -> UIImage {
        let targetSize = CGSize(width: size, height: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        return await Task.detached(priority: .userInitiated) {
            renderer.image { _ in
                let aspect = img.size.width / img.size.height
                let drawRect: CGRect
                if aspect > 1 {
                    let width = size * aspect
                    drawRect = CGRect(x: (size - width) / 2, y: 0, width: width, height: size)
                } else {
                    let height = size / aspect
                    drawRect = CGRect(x: 0, y: (size - height) / 2, width: size, height: height)
                }
                img.draw(in: drawRect)
            }
        }.value
    }
}
