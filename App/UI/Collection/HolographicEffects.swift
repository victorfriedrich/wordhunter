import SwiftUI
import UIKit
import CoreText
import os

// MARK: - Caveat Font Loader (Asset Catalog Data Sets)
//
// Setup required in your asset catalog:
// 1) Add a Data Set named: Caveat-Bold    (drop Caveat-Bold.ttf into it)
// 2) Add a Data Set named: Caveat-Regular (drop Caveat-Regular.ttf into it)

enum CaveatDataFonts {
    struct Loaded {
        let boldPostScriptName: String
        let regularPostScriptName: String
        let ok: Bool
    }

    static let loaded: Loaded = {
        func registerFontFromDataSet(assetName: String) -> String? {
            guard let dataAsset = NSDataAsset(name: assetName) else {
                Log.assets.error("Missing Data Set in asset catalog: \(assetName, privacy: .public)")
                return nil
            }
            guard let provider = CGDataProvider(data: dataAsset.data as CFData),
                  let cgFont = CGFont(provider) else {
                Log.assets.error("Could not create CGFont from Data Set: \(assetName, privacy: .public)")
                return nil
            }

            guard let psName = cgFont.postScriptName as String? else {
                Log.assets.error("PostScript name missing for \(assetName, privacy: .public)")
                return nil
            }

            var error: Unmanaged<CFError>?
            // Already-registered fonts report failure here; that is not fatal,
            // so the PostScript name is returned either way.
            if !CTFontManagerRegisterGraphicsFont(cgFont, &error) {
                let desc = error.map { CFErrorCopyDescription($0.takeUnretainedValue()) as String } ?? "unknown error"
                Log.assets.debug("Font registration for \(assetName, privacy: .public): \(desc, privacy: .public)")
            }

            return psName
        }

        let boldPS = registerFontFromDataSet(assetName: "Caveat-Bold")
        let regularPS = registerFontFromDataSet(assetName: "Caveat-Regular")

        return Loaded(
            boldPostScriptName: boldPS ?? "Caveat-Bold",
            regularPostScriptName: regularPS ?? "Caveat-Regular",
            ok: (boldPS != nil) && (regularPS != nil)
        )
    }()

    static func ensureLoaded() { _ = loaded }

    static func bold(_ size: CGFloat) -> Font {
        ensureLoaded()
        return .custom(loaded.boldPostScriptName, size: size)
    }

    static func regular(_ size: CGFloat) -> Font {
        ensureLoaded()
        return .custom(loaded.regularPostScriptName, size: size)
    }
}

// MARK: - Helper Functions

func holoCSSBackgroundPosition(
    positionPercent: CGFloat,
    containerSize: CGFloat,
    backgroundScale: CGFloat = 3.0
) -> CGFloat {
    let backgroundSize = containerSize * backgroundScale
    return (containerSize - backgroundSize) * (positionPercent / 100.0)
}

func holoCSSAngleToRadians(_ cssDegrees: CGFloat) -> CGFloat {
    (90.0 - cssDegrees) * .pi / 180.0
}

func holoClamp(_ value: Double, min minVal: Double, max maxVal: Double) -> Double {
    max(minVal, min(maxVal, value))
}

// MARK: - Shine Layer

struct ShineLayer: View, Animatable {
    var rotX: Double
    var rotY: Double
    let maxT: Double

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(rotX, rotY) }
        set { rotX = newValue.first; rotY = newValue.second }
    }

    var body: some View {
        Canvas { context, size in
            let tilt = sqrt(rotX * rotX + rotY * rotY)
            let posX = holoClamp(50.0 - rotY * (30.0 / maxT), min: 20, max: 80)
            let posY = holoClamp(50.0 + rotX * (30.0 / maxT), min: 20, max: 80)

            let scale: CGFloat = 3.0
            let offX = holoCSSBackgroundPosition(positionPercent: CGFloat(posX), containerSize: size.width)
            let offY = holoCSSBackgroundPosition(positionPercent: CGFloat(posY), containerSize: size.height)

            let angle = holoCSSAngleToRadians(115.0)
            let virtualW = Double(size.width * scale), virtualH = Double(size.height * scale)
            let halfLen = sqrt(pow(virtualW, 2) + pow(virtualH, 2)) / 2.0
            let cosA = cos(angle), sinA = sin(angle)

            let start = CGPoint(x: (virtualW/2) - cosA * halfLen + Double(offX),
                                y: (virtualH/2) + sinA * halfLen + Double(offY))
            let end = CGPoint(x: (virtualW/2) + cosA * halfLen + Double(offX),
                              y: (virtualH/2) - sinA * halfLen + Double(offY))

            let stops: [Gradient.Stop] = [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.46),
                .init(color: .white.opacity(0.25), location: 0.49),
                .init(color: .white.opacity(0.5), location: 0.50),
                .init(color: .white.opacity(0.25), location: 0.51),
                .init(color: .clear, location: 0.54),
                .init(color: .clear, location: 1.0)
            ]

            context.opacity = 0.0 + (tilt / maxT) * 0.55
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(stops: stops), startPoint: start, endPoint: end))
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - Rainbow Layer

struct RainbowLayer: View, Animatable {
    var rotX: Double
    var rotY: Double
    let maxT: Double

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(rotX, rotY) }
        set { rotX = newValue.first; rotY = newValue.second }
    }

    var body: some View {
        Canvas { context, size in
            let tilt = sqrt(rotX * rotX + rotY * rotY)
            let posX = holoClamp(50.0 - rotY * (35.0 / maxT), min: 15, max: 85)
            let posY = holoClamp(50.0 + rotX * (35.0 / maxT), min: 15, max: 85)

            let scale: CGFloat = 3.0
            let offX = holoCSSBackgroundPosition(positionPercent: CGFloat(posX), containerSize: size.width)
            let offY = holoCSSBackgroundPosition(positionPercent: CGFloat(posY), containerSize: size.height)

            let angle = holoCSSAngleToRadians(108.0)
            let virtualW = Double(size.width * scale), virtualH = Double(size.height * scale)
            let halfLen = sqrt(pow(virtualW, 2) + pow(virtualH, 2)) / 2.0
            let cosA = cos(angle), sinA = sin(angle)

            let start = CGPoint(x: (virtualW/2) - cosA * halfLen + Double(offX),
                                y: (virtualH/2) + sinA * halfLen + Double(offY))
            let end = CGPoint(x: (virtualW/2) + cosA * halfLen + Double(offX),
                              y: (virtualH/2) - sinA * halfLen + Double(offY))

            let stops: [Gradient.Stop] = [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.42),
                .init(color: Color(red: 1.0, green: 0, blue: 0.5).opacity(0.27), location: 0.45),
                .init(color: Color(red: 1.0, green: 0.5, blue: 0).opacity(0.33), location: 0.47),
                .init(color: Color(red: 1.0, green: 1.0, blue: 0).opacity(0.33), location: 0.49),
                .init(color: Color(red: 0, green: 1, blue: 0.5).opacity(0.33), location: 0.51),
                .init(color: Color(red: 0, green: 0.7, blue: 1).opacity(0.33), location: 0.53),
                .init(color: Color(red: 0.55, green: 0, blue: 1).opacity(0.27), location: 0.55),
                .init(color: .clear, location: 0.58),
                .init(color: .clear, location: 1.0)
            ]

            context.opacity = min(tilt / 8.0, 0.95)
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(stops: stops), startPoint: start, endPoint: end))
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - Iridescent Layer

struct IridescentLayer: View, Animatable {
    var rotX: Double
    var rotY: Double
    let maxT: Double

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(rotX, rotY) }
        set { rotX = newValue.first; rotY = newValue.second }
    }

    var body: some View {
        Canvas { context, size in
            let tilt = sqrt(rotX * rotX + rotY * rotY)
            let posX = holoClamp(50.0 + rotY * (35.0 / maxT), min: 15, max: 85)
            let posY = holoClamp(50.0 - rotX * (35.0 / maxT), min: 15, max: 85)

            let scale: CGFloat = 3.0
            let offX = holoCSSBackgroundPosition(positionPercent: CGFloat(posX), containerSize: size.width)
            let offY = holoCSSBackgroundPosition(positionPercent: CGFloat(posY), containerSize: size.height)

            let angle = holoCSSAngleToRadians(55.0)
            let virtualW = Double(size.width * scale), virtualH = Double(size.height * scale)
            let halfLen = sqrt(pow(virtualW, 2) + pow(virtualH, 2)) / 2.0
            let cosA = cos(angle), sinA = sin(angle)

            let start = CGPoint(x: (virtualW/2) - cosA * halfLen + Double(offX),
                                y: (virtualH/2) + sinA * halfLen + Double(offY))
            let end = CGPoint(x: (virtualW/2) + cosA * halfLen + Double(offX),
                              y: (virtualH/2) - sinA * halfLen + Double(offY))

            let stops: [Gradient.Stop] = [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.44),
                .init(color: Color.cyan.opacity(0.21), location: 0.47),
                .init(color: Color.purple.opacity(0.27), location: 0.50),
                .init(color: Color.yellow.opacity(0.21), location: 0.53),
                .init(color: .clear, location: 0.56),
                .init(color: .clear, location: 1.0)
            ]

            context.opacity = min(tilt / 12.0, 0.75)
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(stops: stops), startPoint: start, endPoint: end))
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - Specular Layer

struct SpecularLayer: View, Animatable {
    var rotX: Double
    var rotY: Double
    let maxT: Double

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(rotX, rotY) }
        set { rotX = newValue.first; rotY = newValue.second }
    }

    var body: some View {
        Canvas { context, size in
            let tilt = sqrt(rotX * rotX + rotY * rotY)
            let pxPercent = holoClamp(50.0 - rotY * (25.0 / maxT), min: 25, max: 75)
            let pyPercent = holoClamp(50.0 - rotX * (25.0 / maxT), min: 25, max: 75)
            let centerX = size.width * CGFloat(pxPercent / 100.0)
            let centerY = size.height * CGFloat(pyPercent / 100.0)

            let stops: [Gradient.Stop] = [
                .init(color: .white.opacity(0.8), location: 0.0),
                .init(color: .white.opacity(0.3), location: 0.5),
                .init(color: .clear, location: 1.0)
            ]

            context.opacity = 0.1 + min(tilt / 15.0, 0.5)
            context.addFilter(.blur(radius: 12))

            context.fill(Path(ellipseIn: CGRect(x: centerX - 40, y: centerY - 35, width: 80, height: 70)),
                         with: .radialGradient(Gradient(stops: stops),
                                               center: CGPoint(x: centerX, y: centerY),
                                               startRadius: 0,
                                               endRadius: 50))
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - Grain Overlay

struct GlossyGrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            for _ in 0..<500 {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(0.12)))
            }
        }
    }
}

// MARK: - 3D Perspective Transform

struct CSSPerspectiveTransform: ViewModifier {
    let rotX, rotY, rotZ, perspective: Double
    func body(content: Content) -> some View {
        content.modifier(Perspective3DEffect(rotX: rotX, rotY: rotY, rotZ: rotZ, perspective: perspective))
    }
}

struct Perspective3DEffect: GeometryEffect {
    var rotX, rotY, rotZ, perspective: Double

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(rotX, rotY), rotZ) }
        set { rotX = newValue.first.first; rotY = newValue.first.second; rotZ = newValue.second }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        var t = CATransform3DIdentity
        t.m34 = -1.0 / perspective
        t = CATransform3DRotate(t, CGFloat(rotX * .pi / 180), 1, 0, 0)
        t = CATransform3DRotate(t, CGFloat(rotY * .pi / 180), 0, 1, 0)
        t = CATransform3DRotate(t, CGFloat(rotZ * .pi / 180), 0, 0, 1)
        let cx = size.width / 2, cy = size.height / 2
        var p = ProjectionTransform()
        p.m11 = t.m11 + t.m14 * cx; p.m12 = t.m12 + t.m14 * cy; p.m13 = t.m14
        p.m21 = t.m21 + t.m24 * cx; p.m22 = t.m22 + t.m24 * cy; p.m23 = t.m24
        p.m31 = t.m41 + t.m44 * cx - cx * p.m11 - cy * p.m21
        p.m32 = t.m42 + t.m44 * cy - cx * p.m12 - cy * p.m22
        p.m33 = t.m44 - cx * t.m14 - cy * t.m24
        return p
    }
}

// MARK: - Font Debug Overlay

struct FontDebugOverlay: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Caveat fonts not available")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
            Text("Expected Data Sets: Caveat-Bold, Caveat-Regular")
                .font(.system(size: 12, design: .monospaced))
            Text("Bold PS: \(CaveatDataFonts.loaded.boldPostScriptName)")
                .font(.system(size: 12, design: .monospaced))
            Text("Regular PS: \(CaveatDataFonts.loaded.regularPostScriptName)")
                .font(.system(size: 12, design: .monospaced))

            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 420, height: 220)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
    }
}
