import SwiftUI
import UIKit

@available(iOS 18, *)
struct PolaroidDetailScreen: View {
    let items: [GalleryItem]
    let initialIndex: Int
    let onBack: () -> Void
    let bottomOverlayPadding: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @StateObject private var imageCache = GalleryImageCache()

    @State private var currentIndex: Int
    @State private var currentCaptureIndex: Int = 0
    @State private var rotX: Double = 0
    @State private var rotY: Double = 0
    @State private var lastDragLocation: CGPoint? = nil
    @State private var isDeveloped: Bool = false

    private let baseRotZ: Double = -1.5
    private let maxTilt: Double = 15.0

    init(
        items: [GalleryItem],
        initialIndex: Int,
        bottomOverlayPadding: CGFloat = 0,
        onBack: @escaping () -> Void
    ) {
        self.items = items
        self.initialIndex = initialIndex
        self.bottomOverlayPadding = bottomOverlayPadding
        self.onBack = onBack
        self._currentIndex = State(initialValue: initialIndex)
        CaveatDataFonts.ensureLoaded()
    }

    private var currentItem: GalleryItem? {
        guard currentIndex >= 0 && currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DetailBackground()

            VStack(spacing: 0) {
                backHeader(onBack: onBack)

                Spacer()

                // Floating Navigation Pill
                if let item = currentItem, item.captureRefs.count > 1 {
                    HStack(spacing: 24) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentCaptureIndex = max(0, currentCaptureIndex - 1)
                            }
                            imageCache.preloadFullRes(for: item, captureIndex: currentCaptureIndex)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .disabled(currentCaptureIndex == 0)
                        .opacity(currentCaptureIndex == 0 ? 0.3 : 1.0)
                        .accessibilityLabel("Previous image")

                        Text("\(currentCaptureIndex + 1) of \(item.captureRefs.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GameTheme.navigationDark)
                            .accessibilityHidden(true)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentCaptureIndex = min(item.captureRefs.count - 1, currentCaptureIndex + 1)
                            }
                            imageCache.preloadFullRes(for: item, captureIndex: currentCaptureIndex)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .disabled(currentCaptureIndex == item.captureRefs.count - 1)
                        .opacity(currentCaptureIndex == item.captureRefs.count - 1 ? 0.3 : 1.0)
                        .accessibilityLabel("Next image")
                    }
                    .foregroundStyle(GameTheme.navigationDark)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .systemBackground).opacity(0.85))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                    .padding(.bottom, 24)
                    .zIndex(10) // Prevents the card's invisible padding from blocking touches
                } else {
                    Spacer().frame(height: 64)
                }

                PolaroidCardView(
                    item: currentItem,
                    captureIndex: currentCaptureIndex,
                    isDeveloped: isDeveloped,
                    imageCache: imageCache,
                    rotX: rotX,
                    rotY: rotY,
                    baseRotZ: baseRotZ,
                    maxTilt: maxTilt
                )
                .zIndex(1)
                .if(!voiceOverEnabled) { view in
                    view.gesture(tiltGesture)
                }
                .animation(nil, value: currentIndex)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(currentItem?.word ?? "Word")
                .accessibilityValue(cardAccessibilityValue)
                .accessibilityHint(items.count > 1 ? "Use the filmstrip to change items" : "Shows details")

                Spacer(minLength: 16)

                if items.count > 1 {
                    FilmstripScrubber(
                        items: items,
                        currentIndex: $currentIndex,
                        imageCache: imageCache
                    )
                    .padding(.bottom, 12)
                    .accessibilityLabel("Filmstrip")
                    .accessibilityHint("Select an item to view")
                }
            }
            .padding(.bottom, bottomOverlayPadding)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            isDeveloped = false
            if reduceMotion {
                isDeveloped = true
            } else {
                withAnimation(.easeOut(duration: 1.2)) { isDeveloped = true }
            }
            imageCache.preloadAround(index: currentIndex, items: items)
        }
        .onChange(of: currentIndex) { _, newIndex in
            currentCaptureIndex = 0 // Reset photo when changing words
            imageCache.preloadAround(index: newIndex, items: items)
            UIAccessibility.post(
                notification: .announcement,
                argument: "\(newIndex + 1) of \(items.count)"
            )
        }
    }

    private var cardAccessibilityValue: String {
        let translation = currentItem?.translation ?? ""
        let wordPosition = items.isEmpty ? "" : "Word \(currentIndex + 1) of \(items.count)"
        
        var capturePosition = ""
        if let item = currentItem, item.captureRefs.count > 1 {
            capturePosition = "Image \(currentCaptureIndex + 1) of \(item.captureRefs.count)"
        }
        
        let parts = [translation, capturePosition, wordPosition].filter { !$0.isEmpty }
        return parts.joined(separator: ", ")
    }

    // MARK: Tilt Gesture
    private var tiltGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if reduceMotion { return }
                let current = value.location
                if let last = lastDragLocation {
                    let dx = current.x - last.x
                    let dy = current.y - last.y
                    rotY = max(-maxTilt, min(maxTilt, rotY + dx * 0.5))
                    rotX = max(-maxTilt, min(maxTilt, rotX - dy * 0.5))
                }
                lastDragLocation = current
            }
            .onEnded { _ in
                lastDragLocation = nil
                if reduceMotion {
                    rotX = 0
                    rotY = 0
                } else {
                    withAnimation(.interpolatingSpring(stiffness: 140, damping: 15)) {
                        rotX = 0
                        rotY = 0
                    }
                }
            }
    }

    // MARK: Header
    private func backHeader(onBack: @escaping () -> Void) -> some View {
        HStack {
            Button {
                onBack()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 17))
                }
                .foregroundStyle(GameTheme.navigationDark)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Back to collection")
            .accessibilityHint("Returns to the collection")

            Spacer()
        }
        .padding(.horizontal)
        .frame(height: 44)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: Detail Background

private struct DetailBackground: View {
    var body: some View {
        ZStack {
            GameTheme.environmentalGradient
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color(red: 1, green: 0.98, blue: 0.94).opacity(0.6), .clear],
                center: .init(x: 0.85, y: 0.1),
                startRadius: 0,
                endRadius: 600
            )
            .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }
}

// MARK: Small helper

private extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
