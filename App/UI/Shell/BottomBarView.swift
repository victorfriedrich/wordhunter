import SwiftUI
import UIKit

// A custom tab bar is necessary here: the native navigation bar components
// tear down and rebuild their content, and the camera preview has to stay
// alive across tab changes.
//
// Portions adapted from union-tab-view by Ben Sage (Union St), used under the
// MIT license: https://github.com/unionst/union-tab-view
// See THIRD_PARTY_NOTICES.md in the repository root for the full notice.
@available(iOS 17.0, *)
struct BottomBarView: View {
    @Binding var selectedTab: AppTab

    let bottomInset: CGFloat
    let showCapture: Bool
    let isCaptureEnabled: Bool
    let onCapture: () -> Void

    @State private var captureHapticTrigger = false
    @State private var isPressed = false

    // Separate release "pop" phase (keeps visuals simple, no extra layers)
    @State private var releasePopOuterScale: CGFloat = 1.0
    @State private var releasePopInnerScale: CGFloat = 1.0

    private let barHeight: CGFloat = 58
    private let itemMinWidth: CGFloat = 86
    private let horizontalPadding: CGFloat = 20
    private let glassInnerPadding: CGFloat = 4

    private var tabs: [AppTab] { [.scan, .collection, .categories, .achievements] }

    private var selectedIndex: Int {
        tabs.firstIndex(of: selectedTab) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            if showCapture {
                captureButton
                    .padding(.bottom, 20)
                    .transition(.opacity)
            }

            if #available(iOS 26.0, *) {
                iOS26Bar
            } else {
                legacyBar
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, -bottomInset + 21)
    }

    @available(iOS 26.0, *)
    private var iOS26Bar: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                tabItemView(tab, isSelected: selectedIndex == index)
                    .padding(.vertical, 4)
                    .frame(minWidth: itemMinWidth)
                    .frame(height: barHeight)
            }
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
        .background {
            GeometryReader { geo in
                BottomBarInteractiveSegmentedControl(
                    size: geo.size,
                    barTint: .gray.opacity(0.15),
                    selectedIndex: Binding(
                        get: { selectedIndex },
                        set: { newIndex in
                            guard tabs.indices.contains(newIndex) else { return }
                            selectedTab = tabs[newIndex]
                        }
                    ),
                    itemCount: tabs.count
                )
            }
        }
        .padding(glassInnerPadding)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var legacyBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                tabItemView(tab, isSelected: selectedIndex == index)
                    .padding(.vertical, 4)
                    .frame(minWidth: itemMinWidth)
                    .frame(height: barHeight)
            }
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
        .background {
            GeometryReader { geo in
                BottomBarInteractiveSegmentedControl(
                    size: geo.size,
                    barTint: .gray.opacity(0.18),
                    selectedIndex: Binding(
                        get: { selectedIndex },
                        set: { newIndex in
                            guard tabs.indices.contains(newIndex) else { return }
                            selectedTab = tabs[newIndex]
                        }
                    ),
                    itemCount: tabs.count
                )
            }
        }
        .padding(glassInnerPadding)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func tabItemView(_ tab: AppTab, isSelected: Bool) -> some View {
        tabIcon(for: tab)
            .frame(width: 36, height: 36)
            .offset(y: 1)
            .accessibilityHidden(true)
    }

    private var captureButton: some View {
            // Fast, slightly tight press in
            let pressAnimation = Animation.spring(response: 0.15, dampingFraction: 0.7)

            // Slower, bouncier release out.
            // A dampingFraction below ~0.6 naturally creates an overshoot (pop) past 1.0!
            let releaseAnimation = Animation.spring(response: 0.35, dampingFraction: 0.45)

            // Deeper press scales to create more visual contrast
            let outerScale: CGFloat = isPressed ? 0.88 : 1.0
            let innerScale: CGFloat = isPressed ? 0.75 : 1.0

            return ZStack {
                if #available(iOS 26.0, *) {
                    Circle()
                        .fill(.clear)
                        .frame(width: 86, height: 86)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .scaleEffect(outerScale)
                        .animation(isPressed ? pressAnimation : releaseAnimation, value: outerScale)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 68, height: 68)
                        .scaleEffect(innerScale)
                        .animation(isPressed ? pressAnimation : releaseAnimation, value: innerScale)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 86, height: 86)
                        .scaleEffect(outerScale)
                        .animation(isPressed ? pressAnimation : releaseAnimation, value: outerScale)

                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 86, height: 86)
                        .scaleEffect(outerScale)
                        .animation(isPressed ? pressAnimation : releaseAnimation, value: outerScale)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 68, height: 68)
                        .scaleEffect(innerScale)
                        .animation(isPressed ? pressAnimation : releaseAnimation, value: innerScale)
                }
            }
            .opacity(isCaptureEnabled ? 1.0 : 0.5)
            .contentShape(Circle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isCaptureEnabled, !isPressed else { return }
                        isPressed = true
                    }
                    .onEnded { _ in
                        guard isCaptureEnabled else {
                            isPressed = false
                            return
                        }

                        // Finger up: just set isPressed to false.
                        // The releaseAnimation's low damping will cause the natural overshoot.
                        isPressed = false

                        captureHapticTrigger.toggle()
                        onCapture()
                    }
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: captureHapticTrigger)
            .accessibilityLabel("Capture")
            .accessibilityAddTraits(.isButton)
        }

    @ViewBuilder
    private func tabIcon(for tab: AppTab) -> some View {
        switch tab {
        case .scan:
            Image("camera")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 28)

        case .achievements:
            Image("achievements")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 28)

        case .collection:
            Image("photos")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 28)

        case .categories:
            Image("clipboard")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 30)
        }
    }
}

@MainActor
private struct BottomBarInteractiveSegmentedControl: UIViewRepresentable {
    var size: CGSize
    var barTint: Color
    @Binding var selectedIndex: Int
    var itemCount: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let items = (0..<max(1, itemCount)).map { _ in "" }
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = selectedIndex

        control.selectedSegmentTintColor = UIColor(barTint)
        control.backgroundColor = .clear

        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.segmentChanged(_:)),
            for: .valueChanged
        )

        hideNonSelectedUIImageViews(in: control)

        return control
    }

    func updateUIView(_ uiView: UISegmentedControl, context: Context) {
        context.coordinator.parent = self

        if uiView.numberOfSegments != itemCount {
            uiView.removeAllSegments()
            for i in 0..<itemCount {
                uiView.insertSegment(withTitle: "", at: i, animated: false)
            }
        }

        uiView.selectedSegmentTintColor = UIColor(barTint)
        uiView.backgroundColor = .clear

        if uiView.selectedSegmentIndex != selectedIndex {
            uiView.selectedSegmentIndex = selectedIndex
        }

        hideNonSelectedUIImageViews(in: uiView)

        let labels = ["Scan", "Collection", "Categories", "Achievements"]
        let segmentViews = uiView.subviews.sorted { $0.frame.minX < $1.frame.minX }
        for i in 0..<min(segmentViews.count, labels.count) {
            let v = segmentViews[i]
            v.isAccessibilityElement = true
            v.accessibilityLabel = labels[i]
            v.accessibilityTraits = i == selectedIndex ? [.button, .selected] : [.button]
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        size
    }

    private func hideNonSelectedUIImageViews(in control: UISegmentedControl) {
        DispatchQueue.main.async {
            let subviews = control.subviews
            guard !subviews.isEmpty else { return }

            for subview in subviews {
                if subview is UIImageView && subview != subviews.last {
                    subview.alpha = 0
                }
            }
        }
    }

    final class Coordinator: NSObject {
        var parent: BottomBarInteractiveSegmentedControl

        init(parent: BottomBarInteractiveSegmentedControl) {
            self.parent = parent
        }

        @MainActor @objc func segmentChanged(_ control: UISegmentedControl) {
            parent.selectedIndex = control.selectedSegmentIndex
        }
    }
}
