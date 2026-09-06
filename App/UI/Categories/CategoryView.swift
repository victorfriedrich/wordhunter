import SwiftUI
import UIKit

// Not all category suggestions are available as classification labels
// But in a published app, the model for classification would probably be
// either online or a larger model like moondream, increasing the
// range of objects that can be captured

private enum CategoryLayout {
    static let baseBoxSize: CGFloat = 50
    static let accessibilityBoxSize: CGFloat = 58

    static let baseSpacing: CGFloat = 8
    static let accessibilitySpacing: CGFloat = 10

    static let imageColumnCount: Int = 3
    static let middleRowBoxCount: Int = 2
    static let imageOverlap: CGFloat = 15
    static let tooltipSpacing: CGFloat = 2
    static let horizontalPadding: CGFloat = 20

    static func boxSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? accessibilityBoxSize : baseBoxSize
    }

    static func spacing(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? accessibilitySpacing : baseSpacing
    }

    static func baseImageSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let boxSize = boxSize(for: dynamicTypeSize)
        let spacing = spacing(for: dynamicTypeSize)
        return (boxSize * CGFloat(imageColumnCount)) + (spacing * CGFloat(imageColumnCount - 1))
    }

    static func enlargedImageSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        baseImageSize(for: dynamicTypeSize) + (imageOverlap * 2)
    }

    static func middleSectionHeight(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let boxSize = boxSize(for: dynamicTypeSize)
        let spacing = spacing(for: dynamicTypeSize)
        return (boxSize * 3) + (spacing * 2)
    }
}

@available(iOS 18, *)
private struct SelectedWordInfo: Equatable {
    let categoryID: String
    let wordID: String
    let wordProgress: CategoryWordProgress
    let boxFrame: CGRect

    static func == (lhs: SelectedWordInfo, rhs: SelectedWordInfo) -> Bool {
        lhs.categoryID == rhs.categoryID && lhs.wordID == rhs.wordID && lhs.boxFrame == rhs.boxFrame
    }
}

@available(iOS 18, *)
struct CategoriesView: View {
    @Environment(CategoryProgressStore.self) private var categoryProgressStore
    @Environment(ThumbnailStore.self) private var thumbnailStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let bottomOverlayPadding: CGFloat

    // Selection source of truth (driven by taps on boxes)
    @State private var selectedWordInfo: SelectedWordInfo? = nil

    @State private var tooltipWidth: CGFloat = 0

    private var backgroundColor: Color {
        // TODO: Change this to support light/dark mode and use a different bgDark color
        colorSchemeContrast == .increased ? GameTheme.bgDark : GameTheme.background
    }

    var body: some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width - (CategoryLayout.horizontalPadding * 2)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 40) {
                    Text("Categories")
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(.primary)
                        .padding(.top, 20)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(categoryProgressStore.progress) { progress in
                        CategorySectionView(
                            progress: progress,
                            containerWidth: containerWidth,
                            selectedWordInfo: $selectedWordInfo,
                            thumbnailStore: thumbnailStore
                        )
                    }

                    Spacer().frame(height: bottomOverlayPadding + 60)
                }
                .padding(.horizontal, CategoryLayout.horizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    tooltipOverlay(containerWidth: containerWidth)
                }
                .coordinateSpace(name: "categoryScroll")
            }
            .background(
                backgroundColor.ignoresSafeArea()
                    .onTapGesture {
                        if reduceMotion {
                            selectedWordInfo = nil
                        } else {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.95)) {
                                selectedWordInfo = nil
                            }
                        }
                    }
            )
        }
    }

    private var tooltipTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.97, anchor: .top))
                .combined(with: .offset(y: 8)),
            removal: .opacity
                .combined(with: .scale(scale: 0.98, anchor: .top))
                .combined(with: .offset(y: 8))
        )
    }

    @ViewBuilder
    private func tooltipOverlay(containerWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let info = selectedWordInfo {
                tooltipView(info: info, containerWidth: containerWidth)
                    .transition(tooltipTransition)
                    .id(info.wordID)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.9), value: selectedWordInfo?.wordID)
    }

    private func tooltipView(info: SelectedWordInfo, containerWidth: CGFloat) -> some View {
        let pad = CategoryLayout.horizontalPadding
        let boxCenterX = info.boxFrame.midX - pad
        let defaultX = info.boxFrame.minX - pad
        let effectiveWidth = max(tooltipWidth, CategoryLayout.boxSize(for: dynamicTypeSize) + 28)
        let clampedX = max(0, min(defaultX, containerWidth - effectiveWidth))
        let arrowOffset = boxCenterX - clampedX

        return TooltipView(wordProgress: info.wordProgress, arrowOffset: arrowOffset)
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self) { geo in
                geo.size.width
            } action: { newWidth in
                tooltipWidth = newWidth
            }
            .offset(
                x: clampedX + pad,
                y: info.boxFrame.maxY + CategoryLayout.tooltipSpacing
            )
    }
}

@available(iOS 18.0, *)
private struct CategorySectionView: View {
    let progress: CategoryProgress
    let containerWidth: CGFloat
    @Binding var selectedWordInfo: SelectedWordInfo?
    let thumbnailStore: ThumbnailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView

            CategoryGridView(
                progress: progress,
                containerWidth: containerWidth,
                selectedWordInfo: $selectedWordInfo,
                thumbnailStore: thumbnailStore
            )
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(progress.category.name)
                .font(.title2.weight(.bold))

            Text("\(progress.unlockedCount) of \(progress.totalCount) collected")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(progress.category.name))
        .accessibilityValue(Text("\(progress.unlockedCount) of \(progress.totalCount) words collected"))
        .accessibilityAddTraits(.isHeader)
        .accessibilitySortPriority(2)
    }
}

@available(iOS 18.0, *)
private struct CategoryGridView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let progress: CategoryProgress
    let containerWidth: CGFloat
    @Binding var selectedWordInfo: SelectedWordInfo?
    let thumbnailStore: ThumbnailStore

    private var spacing: CGFloat { CategoryLayout.spacing(for: dynamicTypeSize) }

    private var boxesAlignment: HorizontalAlignment {
        progress.category.imageOnRight ? .leading : .trailing
    }

    var body: some View {
        VStack(alignment: boxesAlignment, spacing: spacing) {
            ForEach(0..<3, id: \.self) { rowIndex in
                fullRowView(for: rowIndex)
            }

            middleSectionView

            if WordCategory.rowCounts.count > 6 {
                ForEach(6..<WordCategory.rowCounts.count, id: \.self) { rowIndex in
                    fullRowView(for: rowIndex)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: progress.category.imageOnRight ? .leading : .trailing)
    }

    @ViewBuilder
    private var middleSectionView: some View {
        ZStack(alignment: progress.category.imageOnRight ? .trailing : .leading) {
            Image(progress.category.id)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: CategoryLayout.enlargedImageSize(for: dynamicTypeSize),
                    height: CategoryLayout.enlargedImageSize(for: dynamicTypeSize)
                )
                .blendMode(.multiply)
                .offset(x: progress.category.imageOnRight ? CategoryLayout.imageOverlap : -CategoryLayout.imageOverlap)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: spacing) {
                if progress.category.imageOnRight {
                    middleBoxesStack
                    Spacer().frame(width: CategoryLayout.baseImageSize(for: dynamicTypeSize))
                } else {
                    Spacer().frame(width: CategoryLayout.baseImageSize(for: dynamicTypeSize))
                    middleBoxesStack
                }
            }
        }
        .frame(height: CategoryLayout.middleSectionHeight(for: dynamicTypeSize))
    }

    private var middleBoxesStack: some View {
        VStack(alignment: progress.category.imageOnRight ? .leading : .trailing, spacing: spacing) {
            ForEach(3..<6, id: \.self) { rowIndex in
                middleRowView(for: rowIndex)
            }
        }
    }

    @ViewBuilder
    private func fullRowView(for rowIndex: Int) -> some View {
        let count = WordCategory.rowCounts[rowIndex]
        let startIndex = WordCategory.rowStartIndices[rowIndex]

        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { position in
                wordBox(at: startIndex + position)
            }
        }
    }

    @ViewBuilder
    private func middleRowView(for rowIndex: Int) -> some View {
        let startIndex = WordCategory.rowStartIndices[rowIndex]

        HStack(spacing: spacing) {
            ForEach(0..<CategoryLayout.middleRowBoxCount, id: \.self) { position in
                wordBox(at: startIndex + position)
            }
        }
    }

    @ViewBuilder
    private func wordBox(at index: Int) -> some View {
        if index < progress.wordProgress.count {
            let item = progress.wordProgress[index]
            WordBoxView(
                wordProgress: item,
                categoryID: progress.category.id,
                thumbnailStore: thumbnailStore,
                selectedWordInfo: $selectedWordInfo
            )
        }
    }
}

@available(iOS 18, *)
private struct TooltipView: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let wordProgress: CategoryWordProgress
    let arrowOffset: CGFloat

    private let arrowHeight: CGFloat = 8

    private var tooltipShadowColor: Color {
        colorSchemeContrast == .increased ? Color.black.opacity(0.18) : GameTheme.boxShadow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(wordProgress.word.lemma)
                .font(.headline)
                .foregroundStyle(.primary)

            if let translation = wordProgress.translation {
                Text(translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .padding(.top, arrowHeight + 10)
        .padding(.bottom, 12)
        .padding(.horizontal, 14)
        .background(
            TooltipShape(arrowOffset: arrowOffset, arrowHeight: arrowHeight)
                .fill(.white)
                .shadow(color: tooltipShadowColor, radius: 6, x: 0, y: 3)
        )
    }
}

private struct TooltipShape: Shape {
    let arrowOffset: CGFloat
    let arrowHeight: CGFloat

    private let arrowWidth: CGFloat = 14
    private let cornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let minArrowX = cornerRadius + (arrowWidth / 2) + 2
        let maxArrowX = rect.width - cornerRadius - (arrowWidth / 2) - 2
        let clampedArrowX = max(minArrowX, min(maxArrowX, arrowOffset))

        let arrowStart = clampedArrowX - (arrowWidth / 2)
        let arrowEnd = clampedArrowX + (arrowWidth / 2)

        path.move(to: CGPoint(x: cornerRadius, y: arrowHeight))
        path.addLine(to: CGPoint(x: arrowStart, y: arrowHeight))
        path.addLine(to: CGPoint(x: clampedArrowX, y: 0))
        path.addLine(to: CGPoint(x: arrowEnd, y: arrowHeight))
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: arrowHeight))
        path.addArc(
            center: CGPoint(x: rect.width - cornerRadius, y: arrowHeight + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.width - cornerRadius, y: rect.height - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: cornerRadius, y: rect.height))
        path.addArc(
            center: CGPoint(x: cornerRadius, y: rect.height - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 0, y: arrowHeight + cornerRadius))
        path.addArc(
            center: CGPoint(x: cornerRadius, y: arrowHeight + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

@available(iOS 18.0, *)
private struct WordBoxView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let wordProgress: CategoryWordProgress
    let categoryID: String
    let thumbnailStore: ThumbnailStore
    @Binding var selectedWordInfo: SelectedWordInfo?

    @State private var thumbnail: UIImage? = nil
    @State private var boxFrame: CGRect = .zero

    private var boxSize: CGFloat {
        CategoryLayout.boxSize(for: dynamicTypeSize)
    }

    private var isSelected: Bool {
        selectedWordInfo?.wordID == wordProgress.word.id &&
        selectedWordInfo?.categoryID == categoryID
    }

    private var emptyBoxShadowColor: Color {
        colorSchemeContrast == .increased ? Color.black.opacity(0.18) : GameTheme.boxShadow
    }

    private var cachedThumbnail: UIImage? {
        guard let ref = wordProgress.captureRef else { return nil }
        let cacheKey = "cat-\(ref.captureId)-\(ref.boundsX)-\(ref.boundsY)-\(ref.boundsWidth)-\(ref.boundsHeight)"
        return ThumbCache.shared.get(cacheKey)
    }

    var body: some View {
        Button(action: toggleSelection) {
            boxContent
        }
        .buttonStyle(.plain)
        .background(frameReader)
        .accessibilityElement()
        .accessibilityLabel(Text(wordProgress.word.lemma))
        .accessibilityValue(Text(accessibilityValueText))
        .accessibilityHint(Text(isSelected ? "Hides details." : "Shows details."))
        .accessibilityInputLabels(accessibilityInputLabels)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: Text(isSelected ? "Hide details" : "Show details")) {
            toggleSelection()
        }
        .task(id: wordProgress.captureRef?.id) {
            await loadThumbnail()
        }
        .onAppear {
            if thumbnail == nil, let cached = cachedThumbnail {
                thumbnail = cached
            }
        }
    }

    private var accessibilityValueText: String {
        var parts: [String] = []
        if let translation = wordProgress.translation, !translation.isEmpty {
            parts.append(translation)
        }
        parts.append(wordProgress.isUnlocked ? "Collected" : "Not collected")
        if isSelected { parts.append("Selected") }
        return parts.joined(separator: ". ")
    }

    private var accessibilityInputLabels: [Text] {
        var labels = [Text(wordProgress.word.lemma)]
        if let translation = wordProgress.translation, !translation.isEmpty {
            labels.append(Text(translation))
        }
        return labels
    }

    private var boxContent: some View {
        ZStack {
            if let thumbnail, wordProgress.isUnlocked {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: boxSize, height: boxSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.5), lineWidth: 2)
                            .blur(radius: 1)
                            .offset(y: 1)
                            .mask(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [.black, .clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                    )
                    .accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .frame(width: boxSize, height: boxSize)
                    .shadow(color: emptyBoxShadowColor, radius: 0, x: 0, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: boxSize, height: boxSize)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: isSelected)
    }

    private var frameReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    boxFrame = geo.frame(in: .named("categoryScroll"))
                }
                .onChange(of: geo.frame(in: .named("categoryScroll"))) { _, newValue in
                    boxFrame = newValue
                }
        }
    }

    private func toggleSelection() {
        let willSelect = !isSelected

        if reduceMotion {
            updateSelection()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                updateSelection()
            }
        }

        if UIAccessibility.isVoiceOverRunning {
            let action = willSelect ? "Details shown." : "Details hidden."
            UIAccessibility.post(notification: .announcement, argument: "\(wordProgress.word.lemma). \(action)")
        }
    }

    private func updateSelection() {
        if isSelected {
            selectedWordInfo = nil
        } else {
            selectedWordInfo = SelectedWordInfo(
                categoryID: categoryID,
                wordID: wordProgress.word.id,
                wordProgress: wordProgress,
                boxFrame: boxFrame
            )
        }
    }

    private func loadThumbnail() async {
        guard let ref = wordProgress.captureRef else {
            thumbnail = nil
            return
        }

        let cacheKey = "cat-\(ref.captureId)-\(ref.boundsX)-\(ref.boundsY)-\(ref.boundsWidth)-\(ref.boundsHeight)"

        if let cached = ThumbCache.shared.get(cacheKey) {
            thumbnail = cached
            return
        }

        if let thumb = thumbnailStore.load(captureId: ref.captureId, bounds: ref.bounds) {
            ThumbCache.shared.set(thumb, forKey: cacheKey)
            thumbnail = thumb
        }
    }
}
