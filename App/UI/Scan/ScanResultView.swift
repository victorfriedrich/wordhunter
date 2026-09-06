import SwiftUI

/// Compatibility type for existing call sites (e.g. WordSearchView).
/// Uses semantic colors where possible to support light and dark mode.
struct AccessiblePalette: Equatable {
    let highContrast: Bool

    // Accent
    var primaryGreen: Color {
        highContrast ? Color(uiColor: .systemGreen).opacity(0.95) : Color(uiColor: .systemGreen)
    }

    var primaryGreenDepth: Color {
        // Slightly deeper tone for layered buttons
        let base = UIColor.systemGreen
        return Color(uiColor: base.withAlphaComponent(highContrast ? 1.0 : 0.90))
    }

    // Text
    var selectedText: Color {
        // Inverts with appearance, stays readable on the green accent.
        Color(uiColor: .systemBackground)
    }

    var unselectedText: Color { .primary }

    // Surfaces
    var unselectedBackground: Color { Color(uiColor: .systemBackground) }

    // Strokes
    var selectedStroke: Color { Color(uiColor: .label).opacity(highContrast ? 0.35 : 0.0) }
}

struct GameTheme {
    static let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let darkGreen = Color(red: 0.16, green: 0.62, blue: 0.28)
    static let background = Color(red: 0.95, green: 0.95, blue: 0.93)

    // X button visuals
    static let xButtonBg = Color(.systemGray6).opacity(0.8)
    static let xButtonIcon = Color.black.opacity(0.72)

    static let boxShadow = Color.black.opacity(0.10)
    static let innerShadow = Color.black.opacity(0.10)

    static let navigationDark = Color(white: 0.25)
    static let bgLight = Color(white: 0.96)
    static let bgMed   = Color(white: 0.91)
    static let bgDark  = Color(white: 0.87)

    static var environmentalGradient: LinearGradient {
        LinearGradient(
            colors: [bgLight, bgMed, bgDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let rowExpandAnimation = Animation.spring(response: 0.495, dampingFraction: 0.85)
    static let rowCollapseAnimation = Animation.spring(response: 0.45, dampingFraction: 0.90)
    static let rowSelectionAnimation = Animation.easeInOut(duration: 0.12)
}

struct PrimaryButtonStyle: ButtonStyle {
    let color: Color
    let depthColor: Color
    let foregroundColor: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var buttonHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 60 : 50
    }

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(depthColor)
                .offset(y: 4)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color)
                .offset(y: configuration.isPressed ? 4 : 0)

            configuration.label
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: configuration.isPressed ? 4 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: buttonHeight)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

@available(iOS 18.0, *)
struct ScanResultView: View {
    @Binding var presentation: ScanResultPresentation?
    let onSave: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(AppDependencies.self) private var deps
    @Environment(WordStore.self) private var wordStore
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var isEjected = false
    @State private var isDeveloped = false
    @State private var showList = false
    @State private var classificationExpanded = false
    @State private var ocrExpanded = false
    @State private var contextExpanded = false
    @State private var isSearchActive = false
    @State private var searchState: WordSearchState?

    // Patch: avoid recomputing allCandidateIds on every keystroke
    @State private var cachedAllCandidateIds: Set<String> = []

    // Patch: pre-computed existingIds for search mode — avoids Set.union on every body evaluation
    @State private var cachedExistingIds: Set<String> = []

    private let polaroidHeight: CGFloat = 330
    private let slotHeight: CGFloat = 28
    private let rowSpacing: CGFloat = 8

    // Preserve existing light look, be dark mode friendly in dark.
    private var viewBackground: Color {
        colorScheme == .dark ? Color(uiColor: .systemBackground) : GameTheme.background
    }

    // Restore the bottom sheet look (white in light mode).
    private var actionBarBackground: Color {
        colorScheme == .dark ? Color(uiColor: .systemBackground) : .white
    }

    private struct Palette: Equatable {
        let highContrast: Bool

        var surfaceElevated: Color { Color(uiColor: .tertiarySystemBackground) }
        var cardBackground: Color { Color(uiColor: .systemBackground) }

        var textPrimary: Color { .primary }
        var textSecondary: Color { .secondary }

        var accent: Color {
            highContrast ? Color(uiColor: .systemGreen).opacity(0.95) : Color(uiColor: .systemGreen)
        }

        var accentDepth: Color {
            let base = UIColor.systemGreen
            return Color(uiColor: base.withAlphaComponent(highContrast ? 1.0 : 0.90))
        }

        var onAccentText: Color { Color(uiColor: .systemBackground) }

        var selectedStroke: Color { Color(uiColor: .label).opacity(highContrast ? 0.35 : 0.0) }
        var unselectedStroke: Color { Color(uiColor: .label).opacity(highContrast ? 0.18 : 0.08) }
        var shadowWeak: Color { Color.black.opacity(0.05) }
        var shadowSelected: Color { Color.black.opacity(0.10) }

        var closeIcon: Color { Color(uiColor: .label).opacity(0.72) }
    }

    private var palette: Palette {
        Palette(highContrast: colorSchemeContrast == .increased)
    }

    private var isLargeTextLayout: Bool {
        dynamicTypeSize >= .xxxLarge
    }

    private var rowMinHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 70 : 60
    }

    var body: some View {
        if let p = presentation {
            ZStack(alignment: .top) {
                viewBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        PolaroidCard(
                            image: p.captureImage,
                            isDeveloped: isDeveloped,
                            height: polaroidHeight
                        )
                        .padding(.top, 20)
                        .rotationEffect(.degrees(isEjected ? -1.5 : 0))
                        .offset(y: isEjected ? 0 : -polaroidHeight)
                        .shadow(color: Color.black.opacity(isEjected ? 0.12 : 0), radius: 12, y: 8)
                        .zIndex(2)

                        VStack(spacing: 24) {
                            if p.isProcessing {
                                processingIndicator
                            } else {
                                contentSections(p)
                            }
                            Spacer().frame(height: 140)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 25)
                        .opacity(showList ? 1 : 0)
                        .offset(y: showList ? 0 : 20)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                PrinterSlotView(height: slotHeight, background: viewBackground).zIndex(3)
                headerView.zIndex(4)

                VStack {
                    Spacer()
                    if showList && !p.isProcessing && !isSearchActive {
                        actionBar(presentation: p)
                            .transition(.move(edge: .bottom))
                    }
                }
                .zIndex(5)
            }
            .onAppear {
                searchState = WordSearchState(
                    lexicon: deps.lexiconProvider.sqlite,
                    language: settings.sourceLanguage
                )
                triggerPolaroidAnimation()

                // Initialize cache once
                cachedAllCandidateIds = allCandidateIds(from: p)
            }
            // Patch: only update the cache when a new presentation object is set
            .task(id: presentationIdentity(presentation: presentation)) {
                if let current = presentation {
                    cachedAllCandidateIds = allCandidateIds(from: current)
                } else {
                    cachedAllCandidateIds = []
                }
            }
        }
    }

    private func presentationIdentity(presentation: ScanResultPresentation?) -> String {
        guard let presentation else { return "nil" }
        return String(ObjectIdentifier(presentation.captureImage).hashValue)
    }

    // Patch: ZStack completely eliminates layout tear-down lag by keeping everything
    // in the view hierarchy and just fading/disabling the main content.
    @ViewBuilder
    private func contentSections(_ p: ScanResultPresentation) -> some View {
        ZStack(alignment: .top) {
            
            // MAIN CONTENT
            VStack(spacing: 24) {
                if let section = p.classificationSection {
                    sectionView(section: section, isExpanded: $classificationExpanded, presentation: p, showAddWord: true)
                }

                if let section = p.ocrSection {
                    sectionView(section: section, isExpanded: $ocrExpanded, presentation: p, showAddWord: false)
                }

                if p.isContextLoading || p.contextSection != nil {
                    contextContainerView(
                        isLoading: p.isContextLoading,
                        section: p.contextSection,
                        isExpanded: $contextExpanded,
                        presentation: p
                    )
                }

                if p.unresolvedCount > 0 {
                    unresolvedIndicator(count: p.unresolvedCount)
                }
                if !p.hasAnyResults && !p.isProcessing {
                    noResultsIndicator
                }
            }
            .opacity(isSearchActive ? 0 : 1)
            .allowsHitTesting(!isSearchActive)
            .accessibilityHidden(isSearchActive)

            // SEARCH CONTENT
            if isSearchActive, let searchState {
                searchSection(searchState: searchState, presentation: p)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
    }

    private func sectionView(
        section: CandidateSection,
        isExpanded: Binding<Bool>,
        presentation: ScanResultPresentation,
        showAddWord: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(section.title.uppercased())

            candidateList(section: section, isExpanded: isExpanded.wrappedValue, selectedIds: presentation.selectedIds)
                .compositingGroup()
                .zIndex(1)

            sectionFooter(section: section, isExpanded: isExpanded, showAddWord: showAddWord)
                .zIndex(0)
        }
    }

    private func candidateList(
        section: CandidateSection,
        isExpanded: Bool,
        selectedIds: Set<String>
    ) -> some View {
        let visible = isExpanded
            ? section.candidates
            : Array(section.candidates.prefix(section.defaultVisibleCount))

        return VStack(spacing: rowSpacing) {
            ForEach(visible, id: \.id) { candidate in
                optionRow(candidate: candidate, isSelected: selectedIds.contains(candidate.id))
                    .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func contextContainerView(
        isLoading: Bool,
        section: CandidateSection?,
        isExpanded: Binding<Bool>,
        presentation: ScanResultPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    sectionHeader("FROM CONTEXT")
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.bold))
                        .imageScale(.small)
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                }
                Text("Related words suggested by Apple Intelligence")
                    .font(.caption)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Related words suggested by Apple Intelligence")
            }

            if isLoading {
                VStack(spacing: rowSpacing) {
                    ForEach(0..<3, id: \.self) { _ in shimmerRow }
                }
                .transition(.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading related words")
            } else if let section {
                VStack(alignment: .leading, spacing: 10) {
                    candidateList(section: section, isExpanded: isExpanded.wrappedValue, selectedIds: presentation.selectedIds)
                        .compositingGroup()
                        .zIndex(1)

                    if section.hasMore {
                        expandCollapseButton(hiddenCount: section.hiddenCount, isExpanded: isExpanded)
                            .zIndex(0)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isLoading)
    }

    private func searchSection(searchState: WordSearchState, presentation: ScanResultPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("ADD CUSTOM WORD")
            InlineWordSearchView(
                searchState: searchState,
                existingIds: cachedExistingIds,
                language: settings.sourceLanguage,
                onSelect: { entry in
                    addCustomWord(entry, to: presentation)
                    dismissSearch()
                },
                onDismiss: { dismissSearch() }
            )
        }
    }

    private func optionRow(candidate: ScanCandidate, isSelected: Bool) -> some View {
        let savedCount = wordStore.item(language: candidate.language, lemma: candidate.lemma)?.occurrences
        let showCheckmark = differentiateWithoutColor

        return Button {
            toggleSelection(candidate.id)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if showCheckmark {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? palette.onAccentText : palette.textSecondary)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.lemma)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(isSelected ? palette.onAccentText : palette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let t = candidate.translation {
                        Text(t)
                            .font(.subheadline)
                            .foregroundStyle(isSelected ? palette.onAccentText.opacity(0.88) : palette.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let count = savedCount, isLargeTextLayout {
                        savedBadge(count: count, isSelected: isSelected)
                    }
                }

                Spacer(minLength: 8)

                if let count = savedCount, !isLargeTextLayout {
                    savedBadge(count: count, isSelected: isSelected)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, isLargeTextLayout ? 14 : 0)
            .frame(maxWidth: .infinity, minHeight: rowMinHeight, alignment: .leading)
            .background(isSelected ? palette.accent : palette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        borderColor(isSelected: isSelected, showCheckmark: showCheckmark),
                        lineWidth: borderWidth(isSelected: isSelected, showCheckmark: showCheckmark)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(
                color: isSelected ? palette.shadowSelected : palette.shadowWeak,
                radius: isSelected ? 2 : 0,
                y: isSelected ? 1 : 2
            )
            .animation(GameTheme.rowSelectionAnimation, value: isSelected)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(candidate.lemma)
        .accessibilityValue(accessibilityValue(for: candidate, savedCount: savedCount, isSelected: isSelected))
        .accessibilityHint(isSelected ? "Double-tap to deselect" : "Double-tap to select")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func savedBadge(count: Int, isSelected: Bool) -> some View {
        let textColor = isSelected ? palette.onAccentText.opacity(0.78) : palette.textSecondary

        if isLargeTextLayout {
            Text("Saved \(count) times")
                .font(.footnote.weight(.medium))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Saved \(count)x")
                .font(.caption.weight(.medium))
                .foregroundStyle(textColor)
                .fixedSize()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func sectionFooter(
        section: CandidateSection,
        isExpanded: Binding<Bool>,
        showAddWord: Bool
    ) -> some View {
        Group {
            if isLargeTextLayout {
                VStack(alignment: .leading, spacing: 12) {
                    if section.hasMore { expandCollapseButton(hiddenCount: section.hiddenCount, isExpanded: isExpanded) }
                    if showAddWord { addWordButton }
                }
            } else {
                HStack(spacing: 16) {
                    if section.hasMore { expandCollapseButton(hiddenCount: section.hiddenCount, isExpanded: isExpanded) }
                    if showAddWord { addWordButton }
                }
            }
        }
    }

    private func expandCollapseButton(hiddenCount: Int, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(isExpanded.wrappedValue ? GameTheme.rowCollapseAnimation : GameTheme.rowExpandAnimation) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(isExpanded.wrappedValue ? "Show less" : "Show \(hiddenCount) more")
                    .font(.subheadline.weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(palette.accent)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityHint(isExpanded.wrappedValue ? "Collapse this section" : "Expand this section")
    }

    private var addWordButton: some View {
        Button {
            activateSearch()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)
                Text("Add word")
                    .font(.subheadline.weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .foregroundStyle(palette.accent)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityHint("Search the dictionary to add a custom word")
    }

    private func borderColor(isSelected: Bool, showCheckmark: Bool) -> Color {
        if isSelected {
            if showCheckmark { return palette.onAccentText }
            if colorSchemeContrast == .increased { return palette.selectedStroke }
            return .clear
        }
        return palette.unselectedStroke
    }

    private func borderWidth(isSelected: Bool, showCheckmark: Bool) -> CGFloat {
        if isSelected {
            return (showCheckmark || colorSchemeContrast == .increased) ? 2 : 0
        }
        return 1
    }

    private func accessibilityValue(for candidate: ScanCandidate, savedCount: Int?, isSelected: Bool) -> String {
        var parts: [String] = []
        if let translation = candidate.translation { parts.append("Translation: \(translation)") }
        if let savedCount { parts.append("Saved \(savedCount) times") }
        parts.append(isSelected ? "Selected" : "Not selected")
        return parts.joined(separator: ", ")
    }

    private var processingIndicator: some View {
        HStack(spacing: 12) {
            ProgressView().tint(palette.accent)
            Text("Analyzing...")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyzing image")
        .accessibilityValue("Please wait")
    }

    private var noResultsIndicator: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Color(uiColor: .systemGray3))
                .accessibilityHidden(true)
            Text("No words found")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }

    private func unresolvedIndicator(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(Color(uiColor: .systemGray))
                .accessibilityHidden(true)
            Text("\(count) unrecognized")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var shimmerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .systemGray5))
                    .frame(width: 100, height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .systemGray6))
                    .frame(width: 140, height: 12)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(minHeight: rowMinHeight)
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: palette.shadowWeak, radius: 0, y: 2)
        .modifier(ShimmerModifier())
        .accessibilityHidden(true)
    }

    private var headerView: some View {
        HStack {
            Button {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    presentation = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.closeIcon)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .brightness(0.05)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("Close")
            .accessibilityHint("Dismiss scan results")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func actionBar(presentation: ScanResultPresentation) -> some View {
        let isEmpty = presentation.selectedIds.isEmpty
        let buttonTitle = dynamicTypeSize.isAccessibilitySize
            ? (isEmpty ? "Select a word" : "Continue")
            : (isEmpty ? "What did you capture?" : "Continue")

        return VStack(spacing: 0) {
            Button(action: onSave) { Text(buttonTitle) }
                .buttonStyle(
                    PrimaryButtonStyle(
                        color: isEmpty ? Color(uiColor: .systemGray5) : palette.accent,
                        depthColor: isEmpty ? Color(uiColor: .systemGray4) : palette.accentDepth,
                        foregroundColor: isEmpty ? Color(uiColor: .label).opacity(0.6) : palette.onAccentText
                    )
                )
                .disabled(isEmpty)
                .accessibilityHint(isEmpty ? "Select at least one word to continue" : "Continue with selected words")
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
        }
        .background(actionBarBackground.ignoresSafeArea())
    }

    private func activateSearch() {
        Haptics.lightImpact()

        if let p = presentation {
            cachedExistingIds = p.selectedIds.union(cachedAllCandidateIds)
        }

        withAnimation(.easeOut(duration: 0.15)) {
            isSearchActive = true
        }
    }

    private func dismissSearch() {
        withAnimation(.easeOut(duration: 0.15)) {
            isSearchActive = false
        }
        searchState?.clear()
    }

    private func toggleSelection(_ id: String) {
        guard var p = presentation else { return }
        if p.selectedIds.contains(id) {
            p.selectedIds.remove(id)
        } else {
            p.selectedIds.insert(id)
        }
        presentation = p
    }

    private func addCustomWord(_ entry: LexiconEntry, to presentation: ScanResultPresentation) {
        guard var p = self.presentation else { return }
        let candidate = ScanCandidate(
            language: settings.sourceLanguage,
            lemma: entry.lemma,
            translation: entry.translation,
            source: .classification,
            bounds: nil,
            confidence: 1.0,
            originLabel: entry.translation
        )
        if let section = p.classificationSection {
            var candidates = section.candidates
            candidates.insert(candidate, at: 0)
            p.classificationSection = CandidateSection(
                id: section.id,
                title: section.title,
                candidates: candidates,
                defaultVisibleCount: section.defaultVisibleCount + 1
            )
        } else {
            p.classificationSection = CandidateSection(
                id: "classification",
                title: "From Image",
                candidates: [candidate],
                defaultVisibleCount: 1
            )
        }
        p.selectedIds.insert(candidate.id)
        self.presentation = p

        cachedAllCandidateIds.insert(candidate.id)
        cachedExistingIds.insert(candidate.id)
    }

    private func allCandidateIds(from presentation: ScanResultPresentation) -> Set<String> {
        var ids = Set<String>()
        [presentation.classificationSection, presentation.ocrSection, presentation.contextSection]
            .compactMap { $0 }
            .forEach { ids.formUnion($0.candidates.map(\.id)) }
        return ids
    }

    private func triggerPolaroidAnimation() {
        if reduceMotion {
            isEjected = true
            isDeveloped = true
            showList = true
            return
        }
        withAnimation(.interpolatingSpring(mass: 1.0, stiffness: 72, damping: 15, initialVelocity: 1.5)) {
            isEjected = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Haptics.mediumImpact()
        }
        withAnimation(.easeIn(duration: 2.0).delay(0.2)) {
            isDeveloped = true
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.45)) {
            showList = true
        }
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.4), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width)
                        .clipped()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

struct PolaroidCard: View {
    let image: UIImage
    let isDeveloped: Bool
    let height: CGFloat

    private var imageSize: CGFloat { height * 0.72 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(white: 0.1)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: imageSize, height: imageSize)
                    .clipped()
                    .saturation(isDeveloped ? 1.0 : 0.0)
                    .brightness(isDeveloped ? 0 : 0.3)
                    .opacity(isDeveloped ? 1.0 : 0.6)
            }
            .frame(width: imageSize, height: imageSize)
            .padding(.top, 12)
            .padding(.horizontal, 12)
            Spacer().frame(height: 33)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}

struct PrinterSlotView: View {
    let height: CGFloat
    let background: Color

    var body: some View {
        background
            .frame(height: height + 100)
            .offset(y: -100)
            .ignoresSafeArea(edges: .top)
            .accessibilityHidden(true)
    }
}
