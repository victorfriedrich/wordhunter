import SwiftUI

@available(iOS 17.0, *)
@MainActor
@Observable
final class WordSearchState {
    var query: String = ""
    var results: [LexiconEntry] = []
    var isSearching: Bool = false
    var isExpanded: Bool = false

    static let collapsedCount = 5

    private var searchTask: Task<Void, Never>?
    private let lexicon: SQLiteLexicon?
    let language: Language

    init(lexicon: SQLiteLexicon?, language: Language) {
        self.lexicon = lexicon
        self.language = language
    }

    var visibleResults: [LexiconEntry] {
        if isExpanded { return results }
        return Array(results.prefix(Self.collapsedCount))
    }

    var hasMore: Bool { results.count > Self.collapsedCount }
    var hiddenCount: Int { max(0, results.count - Self.collapsedCount) }

    func search(_ newQuery: String) {
        searchTask?.cancel()

        guard !newQuery.isEmpty else {
            query = ""
            results = []
            isSearching = false
            isExpanded = false
            return
        }

        // Capture references so the Task doesn’t strongly depend on self
        let lexicon = self.lexicon
        let language = self.language

        searchTask = Task {
            // 1. Debounce to prevent SwiftUI @Observable churn on every keystroke
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            // 2. Publish searching state
            await MainActor.run {
                self.isSearching = true
            }

            // 3. Do heavy work off main thread
            let trimmedQuery = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            var entries: [LexiconEntry] = []

            if language == .english {
                // English has no dictionary to cross-reference, so we artificially
                // yield the typed text as a valid addable entry.
                if !trimmedQuery.isEmpty {
                    let syntheticEntry = LexiconEntry(
                        wordId: Int64(abs(trimmedQuery.hashValue)),
                        lemma: trimmedQuery,
                        translation: nil,
                        language: .english,
                        isFlagged: false,
                        isBaseVocab: false
                    )
                    entries = [syntheticEntry]
                }
            } else if let lexicon {
                entries = await lexicon.searchByPrefixAsync(newQuery, language: language, limit: 20)
            }

            guard !Task.isCancelled else { return }

            // 4. Publish results back on the main actor all at once
            await MainActor.run {
                self.query = newQuery
                self.results = entries
                self.isExpanded = false
                self.isSearching = false
            }
        }
    }

    func clear() {
        searchTask?.cancel()
        query = ""
        results = []
        isSearching = false
        isExpanded = false
    }
}

@available(iOS 17.0, *)
struct InlineWordSearchView: View {
    var searchState: WordSearchState
    let existingIds: Set<String>
    let language: Language
    let onSelect: (LexiconEntry) -> Void
    let onDismiss: () -> Void

    // Decouple TextField editing from @Observable to avoid full-tree invalidation per keystroke
    @State private var localQuery: String = ""
    @FocusState private var isTextFieldFocused: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var palette: AccessiblePalette {
        AccessiblePalette(highContrast: colorSchemeContrast == .increased)
    }

    private var useVerticalSearchFieldLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var searchIconSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 20 : 18
    }

    private var clearIconSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 22 : 20
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField

            if !localQuery.isEmpty {
                resultsView
            }
        }
        .task {
            // Sync local query with search state (e.g. if re-entering search)
            localQuery = searchState.query
            try? await Task.sleep(for: .milliseconds(350))
            isTextFieldFocused = true
        }
        .onDisappear {
            isTextFieldFocused = false
        }
    }

    private var searchField: some View {
        Group {
            if useVerticalSearchFieldLayout {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: searchIconSize, weight: .semibold))
                            .foregroundStyle(palette.primaryGreen)
                            .accessibilityHidden(true)

                        field
                    }

                    HStack(spacing: 12) {
                        clearButton
                            .opacity(localQuery.isEmpty ? 0 : 1)
                            .disabled(localQuery.isEmpty)

                        cancelButton
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: searchIconSize, weight: .semibold))
                        .foregroundStyle(palette.primaryGreen)
                        .accessibilityHidden(true)

                    field

                    clearButton
                        .opacity(localQuery.isEmpty ? 0 : 1)
                        .disabled(localQuery.isEmpty)

                    cancelButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 0, y: 2)
    }

    private var field: some View {
        TextField("Search dictionary", text: $localQuery)
        .font(.system(.body, design: .rounded))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($isTextFieldFocused)
        .submitLabel(.done)
        .accessibilityLabel("Search dictionary")
        .accessibilityHint("Enter a word to add")
        .onChange(of: localQuery) { _, newValue in
            searchState.search(newValue)
        }
        .onSubmit {
            if let first = searchState.visibleResults.first,
               !existingIds.contains(candidateId(for: first)) {
                onSelect(first)
            }
        }
    }

    private var clearButton: some View {
        Button {
            Haptics.lightImpact()
            localQuery = ""
            searchState.clear()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: clearIconSize))
                .foregroundStyle(Color(.systemGray3))
        }
        .accessibilityLabel("Clear search")
    }

    private var cancelButton: some View {
        Button {
            Haptics.lightImpact()
            isTextFieldFocused = false
            onDismiss()
        } label: {
            Text("Cancel")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.primaryGreen)
        }
        .accessibilityHint("Close word search")
    }

    private var effectiveQuery: String {
        let stripped = language.strippingArticle(from: localQuery)
        return stripped.isEmpty ? localQuery : stripped
    }

    @ViewBuilder
    private var resultsView: some View {
        // If the query changed but searchState hasn't caught up due to the debounce, show searching
        if searchState.isSearching || searchState.query != localQuery {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.9)
                Text("Searching...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Searching dictionary")
        } else if searchState.results.isEmpty {
            emptyState
        } else {
            // Lazy layout reduces the chance of a small hitch when results appear
            ScrollView {
                LazyVStack(spacing: 8) {
                    let query = effectiveQuery
                    ForEach(searchState.visibleResults, id: \.wordId) { entry in
                        let id = candidateId(for: entry)
                        let isAlreadyAdded = existingIds.contains(id)

                        AutocompleteRow(
                            entry: entry,
                            query: query,
                            language: language,
                            isAlreadyAdded: isAlreadyAdded,
                            onTap: {
                                guard !isAlreadyAdded else { return }
                                Haptics.mediumImpact()

                                // Keep focus stable so the keyboard accessory doesn't rebuild mid tap.
                                isTextFieldFocused = true

                                onSelect(entry)
                            }
                        )
                    }

                    if !searchState.isExpanded && searchState.hasMore {
                        Button {
                            Haptics.lightImpact()
                            withAnimation(.easeOut(duration: 0.2)) {
                                searchState.isExpanded = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Show \(searchState.hiddenCount) more")
                                    .font(.subheadline.weight(.medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(palette.primaryGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.04), radius: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Show more search results")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(Color(.systemGray3))
                .accessibilityHidden(true)

            Text("No matches found")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Check your spelling")
                .font(.caption)
                .foregroundStyle(Color(.systemGray3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }

    private func candidateId(for entry: LexiconEntry) -> String {
        "\(language.rawValue)::\(entry.lemma.lowercased())"
    }
}

@available(iOS 17.0, *)
private struct AutocompleteRow: View {
    let entry: LexiconEntry
    let query: String
    let language: Language
    let isAlreadyAdded: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    private var palette: AccessiblePalette {
        AccessiblePalette(highContrast: colorSchemeContrast == .increased)
    }

    private var trailingIconSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 22 : 20
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                if differentiateWithoutColor {
                    Image(systemName: isAlreadyAdded ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: trailingIconSize, weight: .semibold))
                        .foregroundStyle(isAlreadyAdded ? .secondary : palette.primaryGreen)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    highlightedLemma(entry.lemma, query: query)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    if let translation = entry.translation {
                        highlightedTranslation(translation, query: query)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if !differentiateWithoutColor {
                    Image(systemName: isAlreadyAdded ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: trailingIconSize, weight: .semibold))
                        .foregroundStyle(isAlreadyAdded ? .secondary : palette.primaryGreen)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(isAlreadyAdded ? Color(.systemGray6) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 0, y: 2)
            .opacity(isAlreadyAdded ? 0.8 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyAdded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.lemma)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(isAlreadyAdded ? "Already added" : "Double-tap to add this word")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isAlreadyAdded ? .isSelected : [])
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let translation = entry.translation {
            parts.append("Translation: \(translation)")
        }
        parts.append(isAlreadyAdded ? "Already added" : "Not added")
        return parts.joined(separator: ", ")
    }

    private func highlightedLemma(_ text: String, query: String) -> Text {
        guard !query.isEmpty,
              let range = text.range(of: query, options: Self.matchOptions) else {
            return Text(text).foregroundStyle(.primary)
        }

        let before = String(text[text.startIndex..<range.lowerBound])
        let match = String(text[range])
        let after = String(text[range.upperBound...])

        return Text(before).foregroundStyle(.primary.opacity(0.5))
        + Text(match)
            .foregroundStyle(palette.primaryGreen)
            .underline(differentiateWithoutColor)
        + Text(after).foregroundStyle(.primary)
    }

    private func highlightedTranslation(_ translation: String, query: String) -> Text {
        guard !query.isEmpty,
              let range = translation.range(of: query, options: Self.matchOptions) else {
            return Text(translation).foregroundStyle(.secondary)
        }

        let before = String(translation[translation.startIndex..<range.lowerBound])
        let match = String(translation[range])
        let after = String(translation[range.upperBound...])

        return Text(before).foregroundStyle(.secondary)
        + Text(match)
            .foregroundStyle(palette.primaryGreen)
            .underline(differentiateWithoutColor)
        + Text(after).foregroundStyle(.secondary)
    }
}
