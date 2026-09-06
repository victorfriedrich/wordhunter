import SwiftUI
import UIKit
import UniformTypeIdentifiers

@available(iOS 18, *)
struct CollectionScreen: View {
    @Environment(WordStore.self) private var store
    @Environment(AchievementEngine.self) private var achievementEngine
    @Environment(AppSettings.self) private var settings
    @Environment(ThumbnailStore.self) private var thumbnailStore
    @Environment(CategoryProgressStore.self) private var categoryProgressStore
    @Environment(CaptureStore.self) private var captureStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let bottomOverlayPadding: CGFloat

    private let sidePadding: CGFloat = 20
    private let actionCapsuleMinHeight: CGFloat = 36 // Changed to minHeight

    // MARK: Navigation
    @State private var navigationPath = NavigationPath()

    // MARK: List State
    @State private var sortOption: WordSortOption = .dateAdded
    @State private var isSelectMode = false
    @State private var selectedItems: Set<String> = []
    @State private var cachedSortedItems: [WordItem] = []

    // Index lookup for opening detail (avoid searching arrays on tap)
    @State private var indexById: [String: Int] = [:]

    // MARK: Debug/Export State
    @State private var showDebugMenu = false
    @State private var showExportShare = false
    @State private var exportURL: URL? = nil
    @State private var showImportPicker = false
    @State private var importAlert: ImportAlertState? = nil
    @State private var showClassLogShare = false
    @State private var classLogExportURL: URL? = nil
    @State private var showClearClassLogConfirm = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            listView
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Int.self) { index in
                    let items = cachedSortedItems.map { GalleryItem(from: $0) }
                    PolaroidDetailScreen(
                        items: items,
                        initialIndex: index,
                        bottomOverlayPadding: bottomOverlayPadding,
                        onBack: { navigationPath.removeLast() }
                    )
                    .toolbar(.hidden, for: .navigationBar)
                }
        }
        .onAppear { recomputeSortedItems() }
        .onChange(of: sortOption) { _, _ in recomputeSortedItems() }
        .onChange(of: store.changeCount) { _, _ in recomputeSortedItems() }
        .onChange(of: settings.sourceLanguage) { _, _ in recomputeSortedItems() }

        .sheet(isPresented: $showExportShare) {
            if let url = exportURL { ShareSheet(activityItems: [url]) }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.zip]
        ) { result in
            if case .success(let url) = result { performImport(from: url) }
        }
        .sheet(isPresented: $showClassLogShare) {
            if let url = classLogExportURL { ShareSheet(activityItems: [url]) }
        }
        .alert(item: $importAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog("Debug", isPresented: $showDebugMenu, titleVisibility: .visible) {
            debugMenuButtons
        }
        .confirmationDialog("Clear classification log?", isPresented: $showClearClassLogConfirm, titleVisibility: .visible) {
            clearLogButtons
        }
    }

    // MARK: Navigation
    private func openDetail(index: Int) {
        navigationPath.append(index)
    }

    // MARK: Sorting + Index
    private func recomputeSortedItems() {
        let newItems = store.sortedItems(by: sortOption, for: settings.sourceLanguage)
        let newIndexById = Dictionary(uniqueKeysWithValues: newItems.enumerated().map { ($1.stableId, $0) })

        if reduceMotion {
            cachedSortedItems = newItems
            indexById = newIndexById
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                cachedSortedItems = newItems
                indexById = newIndexById
            }
        }
    }
}

// MARK: List View
@available(iOS 18, *)
private extension CollectionScreen {
    var listView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Text("Collection")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                    .padding(.horizontal, sidePadding)
                    .background(Color(.systemBackground))
                    .zIndex(2)
                    .accessibilityAddTraits(.isHeader)

                if !cachedSortedItems.isEmpty {
                    Section {
                        wordListCard
                            .padding(.horizontal, sidePadding)

                        Color.clear.frame(height: bottomOverlayPadding + 100)
                    } header: {
                        pinnedHeader
                    }
                } else {
                    VStack(spacing: 16) {
                        emptyState
                        // debugMenuButton
                    }
                    .padding(.top, 28)
                    .padding(.bottom, bottomOverlayPadding + 100)
                    .padding(.horizontal, sidePadding)
                }
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: Pinned header (sticky action bar)
    var pinnedHeader: some View {
        VStack(spacing: 0) {
            stickyActionBar
        }
        .background(
            Color(.systemBackground)
                .padding(.top, -300)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: Sticky Action Bar
    var stickyActionBar: some View {
        HStack(spacing: 12) {
            sortButtonLabel
            deleteButton
            Spacer()
            // debugMenuButton
        }
        .padding(.vertical, 12)
        .padding(.horizontal, sidePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zIndex(1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Toolbar Actions")
    }

    // MARK: Word List Card
    var wordListCard: some View {
        let corner: CGFloat = 16
        let imageCorner: CGFloat = 8
        let items = cachedSortedItems

        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.stableId) { i, item in
                let originalIndex = indexById[item.stableId] ?? 0

                WordRowView(
                    item: item,
                    isSelectMode: isSelectMode,
                    isSelected: selectedItems.contains(item.stableId),
                    imageCorner: imageCorner,
                    thumbnailStore: thumbnailStore,
                    toggleSelected: {
                        if selectedItems.contains(item.stableId) { selectedItems.remove(item.stableId) }
                        else { selectedItems.insert(item.stableId) }
                    },
                    openDetail: { openDetail(index: originalIndex) }
                )

                if i != items.count - 1 { Divider() }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(RoundedRectangle(cornerRadius: corner).stroke(Color(.systemGray4), lineWidth: 1))
        .background(RoundedRectangle(cornerRadius: corner).fill(Color(.systemGray3)).offset(y: 4))
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image("emptystate")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 220)
                .accessibilityHidden(true)

            Text("No words collected yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: Sort & Action Controls
@available(iOS 18, *)
private extension CollectionScreen {
    var sortButtonLabel: some View {
        Menu {
            Picker("Sort by", selection: $sortOption) {
                ForEach(WordSortOption.allCases) { option in
                    Label(option.displayName, systemImage: option.icon)
                        .tag(option)
                }
            }
        } label: {
            HStack(spacing: 6) {
                // Image(systemName: "arrow.up.arrow.down")
                Text("Sort")
            }
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Color(.systemGray))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: actionCapsuleMinHeight)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(.systemGray5)))
        }
        .layoutPriority(2)
        .accessibilityLabel("Sort")
        .accessibilityHint("Changes the order of words")
    }

    var deleteButton: some View {
        let isArmedDelete = isSelectMode && !selectedItems.isEmpty

        return Button {
            handleDeleteTap()
        } label: {
            HStack(spacing: 6) {
                // Image(systemName: isSelectMode ? (selectedItems.isEmpty ? "xmark" : "trash.fill") : "trash")
                Text(isSelectMode ? (selectedItems.isEmpty ? "Cancel" : "Delete \(selectedItems.count)") : "Delete")
            }
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isArmedDelete ? Color.white : Color(.systemGray))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: actionCapsuleMinHeight)
            .background(isArmedDelete ? Color.black : Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isArmedDelete ? Color.black : Color(.systemGray5)))
        }
        .buttonStyle(.plain)
        .layoutPriority(3)
        .accessibilityLabel(isSelectMode
            ? (selectedItems.isEmpty ? "Cancel selection" : "Delete \(selectedItems.count) words")
            : "Select words to delete")
        .accessibilityHint(isSelectMode
            ? (selectedItems.isEmpty ? "Exits selection mode" : "Deletes selected words")
            : "Enters selection mode")
        .accessibilityValue(isSelectMode ? "Selection mode" : "")
    }

    private func handleDeleteTap() {
        if isSelectMode && !selectedItems.isEmpty {
            let ids = selectedItems
            let itemsToDelete = cachedSortedItems.filter { ids.contains($0.stableId) }

            // Heavy work outside animation to avoid dropping frames.
            store.removeWithCleanup(items: itemsToDelete, captureStore: captureStore, thumbnailStore: thumbnailStore)
            categoryProgressStore.recomputeAllProgress()

            let finishUI = {
                recomputeSortedItems()
                selectedItems.removeAll()
                isSelectMode = false
            }

            if reduceMotion {
                finishUI()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    finishUI()
                }
            }

            UIAccessibility.post(notification: .announcement, argument: "Deleted \(itemsToDelete.count) words")
        } else {
            let finishUI = {
                isSelectMode.toggle()
                if !isSelectMode { selectedItems.removeAll() }
            }

            if reduceMotion {
                finishUI()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    finishUI()
                }
            }

            UIAccessibility.post(
                notification: .announcement,
                argument: isSelectMode ? "Selection mode on" : "Selection mode off"
            )
        }
    }
}

// MARK: Debug Menu
@available(iOS 18, *)
private extension CollectionScreen {
    var debugMenuButton: some View {
        Button { showDebugMenu = true } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(.systemGray))
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More options")
        .accessibilityHint("Opens export, import, and log tools")
    }

    @ViewBuilder var debugMenuButtons: some View {
        Button("Export Data") { performExport() }
        Button("Import Data") { showImportPicker = true }
        Button("Export Classification Log (JSON)") { exportClassificationLog(asJSON: true) }
        Button("Export Classification Log (Text)") { exportClassificationLog(asJSON: false) }
        Button("Clear Classification Log", role: .destructive) { showClearClassLogConfirm = true }
        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder var clearLogButtons: some View {
        Button("Clear Log", role: .destructive) {
            ClassificationLogger.shared.clearLog()
            importAlert = ImportAlertState(title: "Log Cleared", message: "classification_log.jsonl was deleted.")
            UIAccessibility.post(notification: .announcement, argument: "Log cleared")
        }
        Button("Cancel", role: .cancel) {}
    }

    func performExport() {
        let manager = ExportImportManager()
        do {
            let url = try manager.exportData(wordStore: store, achievementEngine: achievementEngine, settings: settings)
            exportURL = url
            showExportShare = true
        } catch {
            importAlert = ImportAlertState(title: "Export Failed", message: error.localizedDescription)
            UIAccessibility.post(notification: .announcement, argument: "Export failed")
        }
    }

    func exportClassificationLog(asJSON: Bool) {
        let logger = ClassificationLogger.shared
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let url: URL
            if asJSON {
                let entries = logger.getAllEntries()
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(entries)
                url = tempDir.appendingPathComponent("classification_log.json")
                try data.write(to: url, options: .atomic)
            } else {
                let text = logger.exportLogAsString()
                url = tempDir.appendingPathComponent("classification_log.txt")
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
            classLogExportURL = url
            showClassLogShare = true
        } catch {
            importAlert = ImportAlertState(title: "Export Failed", message: error.localizedDescription)
            UIAccessibility.post(notification: .announcement, argument: "Export failed")
        }
    }

    func performImport(from url: URL) {
        let manager = ExportImportManager()
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let summary = try manager.importData(from: url, wordStore: store, achievementEngine: achievementEngine, settings: settings)
            recomputeSortedItems()
            importAlert = ImportAlertState(
                title: "Import Successful",
                message: "Imported \(summary.wordsImported) words, \(summary.capturesImported) captures, \(summary.thumbnailsImported) thumbnails, \(summary.achievementsImported) achievements."
            )
            UIAccessibility.post(notification: .announcement, argument: "Import successful")
        } catch {
            importAlert = ImportAlertState(title: "Import Failed", message: error.localizedDescription)
            UIAccessibility.post(notification: .announcement, argument: "Import failed")
        }
    }
}

// MARK: Word Row View
@available(iOS 18.0, *)
private struct WordRowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: WordItem
    let isSelectMode: Bool
    let isSelected: Bool
    let imageCorner: CGFloat
    let thumbnailStore: ThumbnailStore
    let toggleSelected: () -> Void
    let openDetail: () -> Void

    @State private var thumb: UIImage? = nil

    private var captureCount: Int { item.captureRefs.count }

    private var isLargeType: Bool {
        // "Large sizes" for layout purposes
        dynamicTypeSize >= .accessibility1
    }

    private var thumbSize: CGFloat {
        isLargeType ? 56 : 44
    }

    private var rowPadding: CGFloat {
        isLargeType ? 18 : 16
    }

    var body: some View {
        Button {
            if reduceMotion {
                if isSelectMode { toggleSelected() }
                else { openDetail() }
            } else {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    if isSelectMode { toggleSelected() }
                    else { openDetail() }
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if isSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? GameTheme.green : Color(.systemGray3))
                        .accessibilityHidden(true)
                }

                // Thumbnail + (only for accessibility large type) image info under thumbnail
                VStack(spacing: isLargeType ? 6 : 4) {
                    thumbnailView

                    if isLargeType, captureCount > 1 {
                        thumbnailMeta
                    }
                }
                .frame(width: thumbSize, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.lemma)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    // If no translation, show empty string (not a dash)
                    Text(item.translation ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                // Default placement: right side, vertically centered
                if !isLargeType, captureCount > 1 {
                    thumbnailMeta
                        .padding(.trailing, 4)
                }

                // Keep chevron for navigation affordance, but reduce clutter on very large type.
                if !isLargeType {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(.systemGray3))
                        .accessibilityHidden(true)
                }
            }
            .padding(rowPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.lemma)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(isSelectMode
            ? (isSelected ? "Double tap to deselect" : "Double tap to select")
            : "Double tap to view details")
        .accessibilityAddTraits(isSelectMode && isSelected ? .isSelected : [])
        .task(id: item.latestCaptureRef?.captureId) { await loadThumb() }
    }

    private var accessibilityValueText: String {
        var parts: [String] = []
        if let t = item.translation, !t.isEmpty { parts.append(t) }
        if captureCount > 1 { parts.append("\(captureCount) photos") }
        if isSelectMode { parts.append(isSelected ? "Selected" : "Not selected") }
        return parts.joined(separator: ", ")
    }

    private var thumbnailMeta: some View {
        Text("\(captureCount)")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color(.systemGray2))
            .accessibilityHidden(true)
    }

    private var thumbnailView: some View {
        ZStack {
            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(.systemGray5)
                    .overlay(Image(systemName: "photo").foregroundStyle(Color(.systemGray3)))
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: imageCorner))
        .overlay(RoundedRectangle(cornerRadius: imageCorner).stroke(Color.black.opacity(0.05)))
        .accessibilityHidden(true)
    }

    private func loadThumb() async {
        guard let ref = item.latestCaptureRef else { return }
        let cacheKey = "coll-\(ref.captureId)-\(ref.boundsX)"

        if let cached = ThumbCache.shared.get(cacheKey) {
            thumb = cached
            return
        }

        if let diskThumb = await thumbnailStore.loadAsync(captureId: ref.captureId, bounds: ref.bounds) {
            ThumbCache.shared.set(diskThumb, forKey: cacheKey)
            thumb = diskThumb
        }
    }
}

// MARK: Supporting Types
private struct ImportAlertState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
