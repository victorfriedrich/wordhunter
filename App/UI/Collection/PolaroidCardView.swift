import SwiftUI
import UIKit

// MARK: - PolaroidCardView
//
// The visual polaroid card: paper background, photo, caption text,
// holographic overlays, 3D perspective transform, and drop shadows.

@available(iOS 18, *)
struct PolaroidCardView: View {
    let item: GalleryItem?
    let captureIndex: Int
    let isDeveloped: Bool
    @ObservedObject var imageCache: GalleryImageCache
    let rotX: Double
    let rotY: Double
    let baseRotZ: Double
    let maxTilt: Double

    // 1. Read the current dynamic type size
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let paperWidth: CGFloat = 336
    private let paperHeight: CGFloat = 403
    private let photoSize: CGFloat = 302
    private let captionWidth: CGFloat = 300

    // 2. Helper to determine if we are at an accessibility font size
    private var isLargeText: Bool {
        dynamicTypeSize >= .accessibility1
    }

    var body: some View {
        cardContent
            // Pad so drawingGroup has room for 3D-tilted corners + shadows
            .padding(50)
            .modifier(CSSPerspectiveTransform(
                rotX: rotX,
                rotY: rotY,
                rotZ: baseRotZ + (rotY * 0.05),
                perspective: 800
            ))
            .compositingGroup()
            .drawingGroup(opaque: false, colorMode: .linear)
            .shadow(color: .black.opacity(0.035), radius: 2, y: 2)
            .shadow(color: .black.opacity(0.060), radius: 10, y: 10)
            .shadow(color: .black.opacity(0.070), radius: 22, y: 20)
            .shadow(color: .black.opacity(0.045), radius: 34, y: 32)
            .padding(-50) // restore layout footprint
    }

    private var cardContent: some View {
        ZStack {
            // Paper + photo
            VStack(spacing: 0) {
                ZStack {
                    PolaroidImageView(item: item, captureIndex: captureIndex, isDeveloped: isDeveloped, imageCache: imageCache)
                        .frame(width: photoSize, height: photoSize)

                    GlossyGrainOverlay().opacity(0.20).blendMode(.overlay)

                    RainbowLayer(rotX: rotX, rotY: rotY, maxT: maxTilt)
                    IridescentLayer(rotX: rotX, rotY: rotY, maxT: maxTilt)
                    ShineLayer(rotX: rotX, rotY: rotY, maxT: maxTilt)
                    SpecularLayer(rotX: rotX, rotY: rotY, maxT: maxTilt)
                }
                .frame(width: photoSize, height: photoSize)
                .clipShape(RoundedRectangle(cornerRadius: 1))

                Spacer().frame(height: 68)
            }
            .frame(width: paperWidth, height: paperHeight)
            .background(paperBackground)
            .clipShape(RoundedRectangle(cornerRadius: 2))

            // Caption text
            captionOverlay
        }
    }

    private var captionOverlay: some View {
        let word = item?.word ?? ""
        let translation = item?.translation

        return VStack(spacing: 0) {
            Text(word)
                .font(CaveatDataFonts.bold(34))
                .foregroundColor(Color(white: 0.23))
                .lineLimit(1)
                .minimumScaleFactor(0.5) // Allow it to shrink down more if needed
                .padding(.trailing, 3)

            if let trans = translation {
                Text(trans)
                    .font(CaveatDataFonts.regular(26))
                    .foregroundColor(Color(white: 0.33))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5) // Allow it to shrink down more if needed
                    // 3. Apply tighter padding when sizes get massive
                    .padding(.top, isLargeText ? -16 : -6)
                    .padding(.trailing, 3)
            }
        }
        // 4. Cap the text growth so it never completely shatters the fixed polaroid dimensions
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .frame(width: captionWidth)
        .multilineTextAlignment(.center)
        // 5. Nudge it up a tiny bit to counteract the taller line heights of massive text
        .offset(y: isLargeText ? 148 : 156)
    }

    private var paperBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.996, green: 0.996, blue: 0.996),
                Color(red: 0.961, green: 0.953, blue: 0.941),
                Color(red: 0.922, green: 0.910, blue: 0.890)
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }
}

// MARK: - Progressive Image View

@available(iOS 18, *)
private struct PolaroidImageView: View {
    let item: GalleryItem?
    let captureIndex: Int
    let isDeveloped: Bool
    @ObservedObject var imageCache: GalleryImageCache

    @State private var asyncThumbnail: UIImage? = nil
    @State private var loadedItemId: String? = nil

    private var displayImage: UIImage? {
        guard let item else { return nil }
        if let full = imageCache.getFullRes(for: item, captureIndex: captureIndex) { return full }
        if let thumb = imageCache.getThumbnail(for: item, captureIndex: captureIndex) { return thumb }
        return asyncThumbnail
    }

    var body: some View {
        ZStack {
            if let img = displayImage {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(img == asyncThumbnail ? .low : .high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
                    .saturation(isDeveloped ? 1.0 : 0.0)
                    .brightness(isDeveloped ? 0 : 0.3)
                    .id("\(item?.id ?? "")-\(captureIndex)")
                    .transition(.opacity)
            } else {
                Color(white: 0.85)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: captureIndex)
        .task(id: "\(item?.id ?? "")-\(captureIndex)") {
            guard let item else { return }
            
            // Only clear the thumbnail cache state immediately if we swipe to a COMPLETELY different word
            if loadedItemId != item.id {
                asyncThumbnail = nil
                loadedItemId = item.id
            }
            
            if imageCache.getThumbnail(for: item, captureIndex: captureIndex) == nil {
                if let thumb = await imageCache.getThumbnailAsync(for: item, captureIndex: captureIndex) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        asyncThumbnail = thumb
                    }
                }
            }
        }
    }
}
