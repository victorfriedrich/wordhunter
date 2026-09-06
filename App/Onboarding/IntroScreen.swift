import SwiftUI

// MARK: - Boot Phase

enum BootPhase: Equatable {
    case splash
    case intro
    case loading
    case app
}

// MARK: - Intro Screen

@available(iOS 18.0, *)
struct IntroScreen: View {

    let onStart: (_ language: Language, _ preloadData: Bool) -> Void

    @State private var selectedLanguage: Language = .spanish
    @State private var preloadData: Bool = true

    @State private var showContent = false
    @State private var showButton = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var isHighContrast: Bool { colorSchemeContrast == .increased }
    private var isLargeText: Bool { dynamicTypeSize >= .xxxLarge }
    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    private let sidePadding: CGFloat = 28

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.95, blue: 0.93)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    characterImage
                        .padding(.top, isAccessibilitySize ? 16 : 12)

                    titleSection
                        .padding(.top, 14)

                    languageSection
                        .padding(.top, 24)

                    dataSection
                        .padding(.top, 28)

                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, sidePadding)
                .frame(maxWidth: .infinity)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 10)
            }
        }
        .safeAreaInset(edge: .bottom) {
            startButton
                .padding(.horizontal, sidePadding)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 6)
                .background(
                    Color(red: 0.95, green: 0.95, blue: 0.93)
                        .ignoresSafeArea(edges: .bottom)
                )
        }
        .onAppear { runEntrance() }
    }

    // MARK: - Entrance

    private func runEntrance() {
        if reduceMotion {
            showContent = true; showButton = true
            return
        }

        withAnimation(.easeOut(duration: 0.45).delay(0.05)) {
            showContent = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Haptics.lightImpact()
        }

        withAnimation(.easeOut(duration: 0.4).delay(0.35)) {
            showButton = true
        }
    }

    // MARK: - Character Artwork

    private var characterImage: some View {
        Group {
            if let uiImage = UIImage(named: "AppIconIntroScreen") {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(GameTheme.green)
                    .frame(height: 100)
            }
        }
        .frame(maxHeight: isAccessibilitySize ? 120 : 160)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: - Title + Description

    private var titleSection: some View {
        VStack(spacing: 6) {
            Text("Word Hunter")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Collect words by taking pictures of things around you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Language Section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("LANGUAGE")

            adaptiveLayout {
                selectionButton(
                    title: Language.spanish.displayName,
                    isSelected: selectedLanguage == .spanish,
                    recommended: true
                ) {
                    selectedLanguage = .spanish
                }

                selectionButton(
                    title: Language.english.displayName,
                    isSelected: selectedLanguage == .english,
                    recommended: false
                ) {
                    selectedLanguage = .english
                    preloadData = false // Preloaded data is Spanish only
                }
            }

            explainerText("No language prerequisites required!")
                .padding(.top, 2)
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("STARTING COLLECTION")

            adaptiveLayout {
                selectionButton(
                    title: "Preloaded",
                    isSelected: preloadData == true,
                    recommended: true,
                    isDisabled: selectedLanguage != .spanish
                ) { preloadData = true }

                selectionButton(
                    title: "Empty Slate",
                    isSelected: preloadData == false,
                    recommended: false
                ) { preloadData = false }
            }

            if selectedLanguage == .spanish {
                explainerText(preloadData ? "See what the app looks like with more words collected." : "Start your own collection.")
                    .padding(.top, 2)
            } else {
                explainerText("Progress is saved per language. Preloaded demo data is currently only available for Spanish.")
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Adaptive Layout

    @ViewBuilder
    private func adaptiveLayout<A: View, B: View>(
        @ViewBuilder content: () -> TupleView<(A, B)>
    ) -> some View {
        let views = content()
        if isLargeText {
            VStack(spacing: 10) { views }
        } else {
            HStack(spacing: 10) { views }
        }
    }

    // MARK: - Selection Button

    private func selectionButton(
        title: String,
        isSelected: Bool,
        recommended: Bool,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let surfaceColor = isSelected ? GameTheme.green : Color(uiColor: .systemBackground)
        let depthColor = isSelected ? GameTheme.darkGreen : Color(uiColor: .systemGray4)
        let textColor = isSelected ? Color(uiColor: .systemBackground) : Color.primary

        let borderColor = isSelected
            ? (isHighContrast ? Color(uiColor: .label).opacity(0.3) : Color.clear)
            : Color(uiColor: .separator).opacity(isHighContrast ? 0.5 : 0.25)
        let borderWidth: CGFloat = isSelected && isHighContrast ? 2 : 1

        let buttonHeight: CGFloat = isAccessibilitySize ? 72 : 64

        return Button {
            withAnimation(.easeInOut(duration: 0.12)) { action() }
            Haptics.mediumImpact()
        } label: {
            HStack(spacing: 6) {
                if differentiateWithoutColor && isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(textColor)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(textColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .buttonStyle(
            DepthButtonStyle(
                color: surfaceColor,
                depthColor: depthColor,
                borderColor: borderColor,
                borderWidth: borderWidth,
                height: buttonHeight,
                recommended: recommended && !isDisabled,
                isSelected: isSelected
            )
        )
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(title)\(recommended && !isDisabled ? ", recommended" : "")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isSelected ? "" : "Double-tap to select")
    }

    // MARK: - Shared

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func explainerText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button {
            Haptics.mediumImpact()
            onStart(selectedLanguage, preloadData)
        } label: {
            Text("Let's Go")
        }
        .buttonStyle(
            PrimaryButtonStyle(
                color: GameTheme.green,
                depthColor: GameTheme.darkGreen,
                foregroundColor: .white
            )
        )
        .accessibilityHint("Start the app with your selected options")
    }
}

// MARK: - Depth Button Style

private struct DepthButtonStyle: ButtonStyle {
    let color: Color
    let depthColor: Color
    let borderColor: Color
    let borderWidth: CGFloat
    let height: CGFloat
    var recommended: Bool = false
    var isSelected: Bool = false

    private let depth: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        let pressedOffset = configuration.isPressed ? depth : 0

        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(depthColor)
                .offset(y: depth)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .offset(y: pressedOffset)

            configuration.label
                .offset(y: pressedOffset)

            if recommended {
                recommendedPill
                    .offset(x: 6, y: -10 + pressedOffset)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .compositingGroup()
        .animation(
            configuration.isPressed ? .easeOut(duration: 0.15) : nil,
            value: configuration.isPressed
        )
    }

    private var recommendedPill: some View {
        Text("Recommended")
            .font(.system(size: 11, weight: .bold))
            .fixedSize(horizontal: true, vertical: true)
            .foregroundStyle(isSelected ? .white : Color(uiColor: .label).opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                isSelected
                    ? AnyShapeStyle(GameTheme.darkGreen)
                    : AnyShapeStyle(Color(uiColor: .systemGray5)),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected
                            ? Color.white.opacity(0.2)
                            : Color(uiColor: .separator).opacity(0.3),
                        lineWidth: 1
                    )
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Splash Screen

struct SplashScreen: View {
    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.95, blue: 0.93)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if let icon = UIImage(named: "AppIcon") {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityHidden(true)
                }

                Text("Word Hunter")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Word Hunter is loading")
    }
}

// MARK: - Loading Screen

struct LoadingScreen: View {
    var status: String = "Preparing your collection…"
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.95, blue: 0.93)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(GameTheme.green)

                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.25)) { appeared = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading. \(status)")
    }
}
