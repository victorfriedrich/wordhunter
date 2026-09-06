import SwiftUI
import UIKit

// MARK: - FilmstripScrubber
//
// Horizontal thumbnail strip for navigating between gallery items.
// Supports: tap to select, drag scrubbing, edge auto-scroll.

@available(iOS 18, *)
struct FilmstripScrubber: View {
    let items: [GalleryItem]
    @Binding var currentIndex: Int
    let imageCache: GalleryImageCache

    let thumbnailSize: CGFloat = 44
    let spacing: CGFloat = 2

    @State private var thumbnails: [String: UIImage] = [:]
    @State private var isDragging = false
    @State private var dragStartOffset: CGFloat = 0
    @State private var manualOffset: CGFloat = 0
    @State private var lastFingerX: CGFloat = 0
    @State private var availableWidth: CGFloat = 0

    private var itemWidth: CGFloat { thumbnailSize + spacing }

    private var totalWidth: CGFloat {
        CGFloat(items.count) * thumbnailSize + CGFloat(max(0, items.count - 1)) * spacing
    }

    private let edgeZoneWidth: CGFloat = 70
    private let maxItemsPerSecond: CGFloat = 12.0
    private let edgeScrollTimer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            let offset: CGFloat = isDragging
                ? clampOffset(dragStartOffset + manualOffset, availableWidth: width)
                : calculateCenteredOffset(availableWidth: width)

            HStack(spacing: spacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    FilmstripThumbnail(
                        item: item,
                        size: thumbnailSize,
                        isSelected: index == currentIndex,
                        thumbnail: thumbnails[item.id]
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectIndex(index)
                    }
                    .accessibilityElement()
                    .accessibilityLabel("\(item.word), image \(index + 1) of \(items.count)")
                    .accessibilityAddTraits(index == currentIndex ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: offset)
            .contentShape(Rectangle())
            .highPriorityGesture(dragGesture(containerWidth: width))
            .onAppear { availableWidth = width }
            .onChange(of: geo.size.width) { _, newWidth in
                availableWidth = newWidth
            }
        }
        .frame(height: thumbnailSize + 6)
        .clipped()
        .onReceive(edgeScrollTimer) { _ in
            guard isDragging, availableWidth > 0, totalWidth > availableWidth else { return }
            handleEdgeScroll()
        }
        .task(id: items.map(\.id)) { await loadAllThumbnails() }
    }


    // MARK: - Drag Gesture

    private func dragGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let fingerX = value.location.x
                lastFingerX = fingerX

                // 1. Initialize drag state
                if !isDragging {
                    isDragging = true
                    availableWidth = containerWidth
                    dragStartOffset = calculateCenteredOffset(availableWidth: containerWidth)
                    manualOffset = 0
                }

                // 2. We NO LONGER set manualOffset to value.translation.width here.
                // The strip stays still, allowing the finger to scrub over it.
                // (manualOffset will only be updated by edgeScrollTimer if needed).

                // 3. Calculate where we currently are
                let currentOffset = clampOffset(
                    dragStartOffset + manualOffset,
                    availableWidth: containerWidth
                )

                // 4. Update the selection based on finger position moving across the static strip
                updateSelectionAtFinger(
                    fingerX: fingerX,
                    offset: currentOffset,
                    availableWidth: containerWidth
                )
            }
            .onEnded { value in
                // Use the current offset without factoring in translation.width
                let finalOffset = clampOffset(
                    dragStartOffset + manualOffset,
                    availableWidth: containerWidth
                )

                updateSelectionAtFinger(
                    fingerX: value.location.x,
                    offset: finalOffset,
                    availableWidth: containerWidth
                )

                // End dragging and animate the strip back to center the selected item
                isDragging = false
                withAnimation(.easeOut(duration: 0.25)) {
                    manualOffset = 0
                }
            }
    }

    // MARK: - Edge Scroll

    private func handleEdgeScroll() {
        let fingerX = lastFingerX
        let currentOffset = dragStartOffset + manualOffset
        let maxScrollPerTick = itemWidth * maxItemsPerSecond / 60.0

        if fingerX < edgeZoneWidth {
            let intensity = pow(1.0 - (fingerX / edgeZoneWidth), 2)
            let scrollAmount = maxScrollPerTick * intensity
            let maxOffset: CGFloat = 0

            if currentOffset < maxOffset {
                manualOffset += scrollAmount
                let clampedTotal = clampOffset(
                    dragStartOffset + manualOffset,
                    availableWidth: availableWidth
                )
                manualOffset = clampedTotal - dragStartOffset
                updateSelectionAtFinger(
                    fingerX: fingerX,
                    offset: clampedTotal,
                    availableWidth: availableWidth
                )
            }
        } else if fingerX > availableWidth - edgeZoneWidth {
            let distanceFromEdge = availableWidth - fingerX
            let intensity = pow(1.0 - (distanceFromEdge / edgeZoneWidth), 2)
            let scrollAmount = maxScrollPerTick * intensity
            let minOffset = availableWidth - totalWidth

            if currentOffset > minOffset {
                manualOffset -= scrollAmount
                let clampedTotal = clampOffset(
                    dragStartOffset + manualOffset,
                    availableWidth: availableWidth
                )
                manualOffset = clampedTotal - dragStartOffset
                updateSelectionAtFinger(
                    fingerX: fingerX,
                    offset: clampedTotal,
                    availableWidth: availableWidth
                )
            }
        }
    }

    // MARK: - Selection

    private func selectIndex(_ index: Int) {
        guard items.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
        imageCache.preloadFullRes(for: items[index], priority: .userInitiated)
        Haptics.lightImpact()
    }

    private func updateSelectionAtFinger(fingerX: CGFloat, offset: CGFloat, availableWidth: CGFloat) {
        guard !items.isEmpty else { return }

        let newIndex: Int

        if totalWidth <= availableWidth {
            let centeredOffset = (availableWidth - totalWidth) / 2
            let positionInStrip = fingerX - centeredOffset
            newIndex = max(0, min(items.count - 1, Int(positionInStrip / itemWidth)))
        } else {
            let positionInStrip = fingerX - offset
            newIndex = max(0, min(items.count - 1, Int(positionInStrip / itemWidth)))
        }

        guard newIndex != currentIndex else { return }
        currentIndex = newIndex
        imageCache.preloadFullRes(for: items[newIndex], priority: .userInitiated)
        Haptics.lightImpact()
    }

    // MARK: - Offset Math

    private func calculateCenteredOffset(availableWidth: CGFloat) -> CGFloat {
        guard items.count > 0, availableWidth > 0 else { return 0 }

        if totalWidth <= availableWidth {
            return (availableWidth - totalWidth) / 2
        }

        let itemCenter = CGFloat(currentIndex) * itemWidth + thumbnailSize / 2
        let targetOffset = availableWidth / 2 - itemCenter
        let maxOffset: CGFloat = 0
        let minOffset = availableWidth - totalWidth
        return max(minOffset, min(maxOffset, targetOffset))
    }

    private func clampOffset(_ offset: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return 0 }

        if totalWidth <= availableWidth {
            return (availableWidth - totalWidth) / 2
        }

        let maxOffset: CGFloat = 0
        let minOffset = availableWidth - totalWidth
        return max(minOffset, min(maxOffset, offset))
    }

    // MARK: - Thumbnail Loading

    private func loadAllThumbnails() async {
        for item in items {
            guard !Task.isCancelled else { return }
            if let thumb = await imageCache.getThumbnailAsync(for: item) {
                thumbnails[item.id] = thumb
            }
        }
    }
}

// MARK: - FilmstripThumbnail

@available(iOS 18, *)
private struct FilmstripThumbnail: View {
    let item: GalleryItem
    let size: CGFloat
    let isSelected: Bool
    let thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumb = thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(white: 0.85)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
        )
        .shadow(
            color: isSelected ? .black.opacity(0.3) : .black.opacity(0.1),
            radius: isSelected ? 4 : 2,
            y: 1
        )
    }
}
