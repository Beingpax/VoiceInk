import OSLog
import SwiftData
import SwiftUI

struct InlineHistoryView: View {
    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "InlineHistoryView"
    )
    private static let searchDebounce = Duration.milliseconds(250)
    private static let pageSize = 20

    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var activeTagFilter: String?
    @State private var expandedId: UUID?
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var showDeleteConfirmation = false
    @State private var isPanelPresented = false
    @State private var panelMode: InlineHistoryPanelMode = .info
    @State private var panelTranscriptionId: UUID?
    @State private var pinnedTranscriptions: [Transcription] = []
    @State private var displayedTranscriptions: [Transcription] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var reloadToken = 0

    private let exportService = VoiceInkCSVExportService()

    /// Cheap sentinel query: any write to the store surfaces here and triggers a reload, without
    /// this view holding the whole table in memory.
    @Query(Self.latestTranscriptionIndicatorDescriptor()) private var latestTranscriptionIndicator: [Transcription]

    // MARK: - Fetching

    private static func latestTranscriptionIndicatorDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// Unpinned transcripts, newest first, walked with a timestamp cursor. Pinned rows are fetched
    /// separately into their own section so they stay visible no matter how far the list is paged.
    private func pageDescriptor(before cursor: Date?) -> FetchDescriptor<Transcription> {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = activeTagFilter

        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )

        descriptor.predicate = #Predicate<Transcription> { transcription in
            transcription.isPinned == false
                && (search.isEmpty
                    || transcription.text.localizedStandardContains(search)
                    || (transcription.enhancedText?.localizedStandardContains(search) ?? false))
                && (tag == nil || transcription.tags.contains(tag!))
                && (cursor == nil || transcription.timestamp < cursor!)
        }

        descriptor.fetchLimit = Self.pageSize
        return descriptor
    }

    private func pinnedDescriptor() -> FetchDescriptor<Transcription> {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = activeTagFilter

        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )

        descriptor.predicate = #Predicate<Transcription> { transcription in
            transcription.isPinned
                && (search.isEmpty
                    || transcription.text.localizedStandardContains(search)
                    || (transcription.enhancedText?.localizedStandardContains(search) ?? false))
                && (tag == nil || transcription.tags.contains(tag!))
        }

        return descriptor
    }

    // MARK: - Derived state

    /// Every row currently on screen, pinned section first.
    private var loadedTranscriptions: [Transcription] {
        pinnedTranscriptions + displayedTranscriptions
    }

    private var selectedTranscriptions: [Transcription] {
        loadedTranscriptions.filter { selection.contains($0.persistentModelID) }
    }

    private var allSelected: Bool {
        !loadedTranscriptions.isEmpty && selection.count >= loadedTranscriptions.count
    }

    private var panelTranscription: Transcription? {
        guard let panelTranscriptionId else { return nil }
        return loadedTranscriptions.first { $0.id == panelTranscriptionId }
    }

    private var knownTags: [String] {
        let tags = loadedTranscriptions.flatMap(\.normalizedTags)
        return Array(Set(tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activeTagFilter != nil
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if !knownTags.isEmpty {
                tagFilterBar
                Divider()
            }

            listContent

            if !selection.isEmpty {
                Divider()
                selectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AppTheme.Motion.quick, value: selection.isEmpty)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $searchText, prompt: Text("Search transcriptions"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openPanel(mode: .historySettings)
                } label: {
                    Label("History Settings", systemImage: "gearshape")
                }
                .help("History settings")
            }
        }
        .sidePanel(
            isPresented: Binding(
                get: { isPanelPresented },
                set: { if !$0 { closePanel() } }
            )
        ) {
            panelContent
        }
        .alert("Delete Selected Items?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive, action: deleteSelectedTranscriptions)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                String(
                    format: String(
                        localized:
                            "This action cannot be undone. Are you sure you want to delete %lld items?"
                    ),
                    Int64(selection.count)
                )
            )
        }
        // A single reload path: search text, tag filter, an external write, or an explicit bump
        // all feed one debounced task, so keystrokes no longer issue a fetch each.
        .task(id: reloadKey) {
            if !searchText.isEmpty {
                try? await Task.sleep(for: Self.searchDebounce)
                guard !Task.isCancelled else { return }
            }
            await loadFirstPage()
        }
    }

    private var reloadKey: String {
        "\(searchText)|\(activeTagFilter ?? "")|\(latestTranscriptionIndicator.first?.id.uuidString ?? "")|\(reloadToken)"
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        if loadedTranscriptions.isEmpty && !isLoading {
            emptyState
        } else {
            List(selection: $selection) {
                if !pinnedTranscriptions.isEmpty {
                    Section("Pinned") {
                        ForEach(pinnedTranscriptions, content: row(for:))
                    }
                }

                Section {
                    ForEach(displayedTranscriptions, content: row(for:))

                    if hasMoreContent {
                        HStack {
                            Spacer()
                            ProgressView().controlSize(.small)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                        .onAppear {
                            Task { await loadNextPage() }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .copyable(selectedTranscriptions.map(\.displayText))
            .onDeleteCommand {
                guard !selection.isEmpty else { return }
                showDeleteConfirmation = true
            }
            .onKeyPress(.space) {
                guard let transcription = firstSelected else { return .ignored }
                toggleExpansion(transcription)
                return .handled
            }
            .onKeyPress(.return) {
                guard let transcription = firstSelected else { return .ignored }
                openPanel(mode: .info, transcriptionID: transcription.id)
                return .handled
            }
        }
    }

    private var firstSelected: Transcription? {
        guard let id = selection.first else { return nil }
        return loadedTranscriptions.first { $0.persistentModelID == id }
    }

    private func row(for transcription: Transcription) -> some View {
        HistoryCardRow(
            transcription: transcription,
            isExpanded: expandedId == transcription.id,
            onToggleExpand: { toggleExpansion(transcription) },
            onShowInfo: { openPanel(mode: .info, transcriptionID: transcription.id) },
            onTogglePin: { togglePin(transcription) },
            onAddTag: { addTag($0, to: transcription) },
            onRemoveTag: { removeTag($0, from: transcription) }
        )
        .tag(transcription.persistentModelID)
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .contextMenu {
            rowContextMenu(for: transcription)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isFiltering {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView(
                "No Transcriptions Yet",
                systemImage: "waveform",
                description: Text("Your transcription history will appear here.")
            )
        }
    }

    @ViewBuilder
    private func rowContextMenu(for transcription: Transcription) -> some View {
        Button(transcription.isPinned ? "Unpin" : "Pin") {
            togglePin(transcription)
        }

        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcription.displayText, forType: .string)
        }

        Button("Show Info") {
            openPanel(mode: .info, transcriptionID: transcription.id)
        }

        Divider()

        Button("Delete", role: .destructive) {
            selection = [transcription.persistentModelID]
            showDeleteConfirmation = true
        }
    }

    // MARK: - Tag filter

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.s) {
                HistoryTagChip(
                    title: String(localized: "All"),
                    isSelected: activeTagFilter == nil
                ) {
                    activeTagFilter = nil
                }

                ForEach(knownTags, id: \.self) { tag in
                    HistoryTagChip(
                        title: tag,
                        isSelected: activeTagFilter == tag
                    ) {
                        activeTagFilter = activeTagFilter == tag ? nil : tag
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.vertical, AppTheme.Spacing.s)
        }
    }

    // MARK: - Selection bar

    private var selectionBar: some View {
        HStack(spacing: AppTheme.Spacing.l) {
            Text(String(format: String(localized: "%lld selected"), Int64(selection.count)))
                .font(AppTheme.Typography.labelEmphasized)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                openPanel(mode: .analysis)
            } label: {
                Label("Analyze", systemImage: "chart.bar.xaxis")
            }

            Button {
                exportService.exportTranscriptionsToCSV(transcriptions: selectedTranscriptions)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Divider().frame(height: 16)

            Button(allSelected ? "Deselect All" : "Select All") {
                if allSelected {
                    selection.removeAll()
                } else {
                    selection = Set(displayedTranscriptions.map(\.persistentModelID))
                }
            }
            .keyboardShortcut("a", modifiers: .command)
        }
        .buttonStyle(.accessoryBar)
        .padding(.horizontal, AppTheme.Spacing.xxl)
        .padding(.vertical, AppTheme.Spacing.s)
        .background(.bar)
    }

    // MARK: - Side panel

    @ViewBuilder
    private var panelContent: some View {
        switch panelMode {
        case .info:
            VStack(spacing: 0) {
                AppPanelHeader(title: "Info", onClose: closePanel)

                if let panelTranscription {
                    TranscriptionInfoPanel(transcription: panelTranscription)
                        .id(panelTranscription.id)
                } else {
                    Spacer()
                }
            }
        case .analysis:
            HistoryAnalysisPanelView(
                transcriptions: selectedTranscriptions,
                onClose: closePanel
            )
            .id(selection.count)
        case .historySettings:
            HistorySettingsPanel(onClose: closePanel)
        }
    }

    private func openPanel(mode: InlineHistoryPanelMode, transcriptionID: UUID? = nil) {
        panelMode = mode
        panelTranscriptionId = transcriptionID
        isPanelPresented = true
    }

    private func closePanel() {
        isPanelPresented = false
        panelMode = .info
    }

    // MARK: - Actions

    private func toggleExpansion(_ transcription: Transcription) {
        withAnimation(AppTheme.Motion.quick) {
            expandedId = expandedId == transcription.id ? nil : transcription.id
        }
    }

    private func togglePin(_ transcription: Transcription) {
        transcription.isPinned.toggle()
        save()
        reloadToken += 1
    }

    private func addTag(_ tag: String, to transcription: Transcription) {
        transcription.addTag(tag)
        save()
    }

    private func removeTag(_ tag: String, from transcription: Transcription) {
        transcription.removeTag(tag)
        save()

        // The tag may have just left the filter bar entirely.
        if activeTagFilter == tag, !knownTags.contains(tag) {
            activeTagFilter = nil
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save transcription change: \(error, privacy: .public)")
        }
    }

    // MARK: - Loading

    @MainActor
    private func loadFirstPage() async {
        isLoading = true
        defer { isLoading = false }

        do {
            pinnedTranscriptions = try modelContext.fetch(pinnedDescriptor())
            let items = try modelContext.fetch(pageDescriptor(before: nil))
            displayedTranscriptions = items
            hasMoreContent = items.count == Self.pageSize
            pruneSelection()
        } catch {
            Self.logger.error("Error loading transcriptions: \(error, privacy: .public)")
        }
    }

    @MainActor
    private func loadNextPage() async {
        guard !isLoading, hasMoreContent, let last = displayedTranscriptions.last else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let newItems = try modelContext.fetch(pageDescriptor(before: last.timestamp))
            let existing = Set(displayedTranscriptions.map(\.persistentModelID))
            displayedTranscriptions.append(
                contentsOf: newItems.filter { !existing.contains($0.persistentModelID) }
            )
            hasMoreContent = newItems.count == Self.pageSize
        } catch {
            Self.logger.error("Error loading more transcriptions: \(error, privacy: .public)")
        }
    }

    /// Selection is keyed on persistent IDs, so entries for rows that are no longer loaded are
    /// dropped rather than silently retaining deleted objects.
    private func pruneSelection() {
        let visible = Set(loadedTranscriptions.map(\.persistentModelID))
        selection.formIntersection(visible)
    }

    // MARK: - Deletion

    private func deleteSelectedTranscriptions() {
        let doomed = selectedTranscriptions

        for transcription in doomed {
            if let urlString = transcription.audioFileURL, let url = URL(string: urlString) {
                try? FileManager.default.removeItem(at: url)
            }

            if expandedId == transcription.id {
                expandedId = nil
            }
            if panelTranscriptionId == transcription.id {
                panelTranscriptionId = nil
                closePanel()
            }

            modelContext.delete(transcription)
        }

        selection.removeAll()
        save()
        NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
        reloadToken += 1
    }
}

// MARK: - Supporting types

private enum InlineHistoryPanelMode {
    case info
    case analysis
    case historySettings
}

extension Transcription {
    /// What the user sees for this transcript — the enhanced text when there is one.
    var displayText: String {
        enhancedText ?? text
    }
}

private struct HistoryTagChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.Typography.captionEmphasized)
                .foregroundStyle(isSelected ? AppTheme.Text.onAccent : AppTheme.Text.secondary)
                .padding(.horizontal, AppTheme.Spacing.m)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(
                    Capsule().fill(isSelected ? AppTheme.Accent.primary : AppTheme.Surface.card)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - History Card Row

private struct HistoryCardRow: View {
    let transcription: Transcription
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onShowInfo: () -> Void
    let onTogglePin: () -> Void
    let onAddTag: (String) -> Void
    let onRemoveTag: (String) -> Void

    @State private var selectedTab: TranscriptionTab = .original
    @State private var isAddingTag = false
    @State private var draftTag = ""
    @FocusState private var isTagFieldFocused: Bool

    private var displayText: String {
        switch selectedTab {
        case .original: return transcription.text
        case .enhanced: return transcription.enhancedText ?? ""
        }
    }

    private var audioURL: URL? {
        guard let urlString = transcription.audioFileURL,
            let url = URL(string: urlString),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                expandedContent
                    .padding(.top, AppTheme.Spacing.s)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.s) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    if transcription.isPinned {
                        Image(systemName: "pin.fill")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Status.warningStrong)
                            .accessibilityLabel("Pinned")
                    }

                    Text(
                        transcription.timestamp,
                        format: .dateTime.month(.abbreviated).day().hour().minute()
                    )
                    .font(AppTheme.Typography.captionEmphasized)
                    .foregroundStyle(.secondary)
                }

                if !isExpanded {
                    Text(transcription.displayText)
                        .font(AppTheme.Typography.label)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                }

                if !transcription.normalizedTags.isEmpty {
                    tagRow
                }
            }

            Spacer(minLength: 0)

            Button(action: onTogglePin) {
                Image(systemName: transcription.isPinned ? "pin.slash" : "pin")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(transcription.isPinned ? "Unpin transcription" : "Pin transcription")
            .accessibilityLabel(transcription.isPinned ? "Unpin transcription" : "Pin transcription")

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(AppTheme.Motion.quick, value: isExpanded)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpand)
    }

    private var tagRow: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(transcription.normalizedTags, id: \.self) { tag in
                HStack(spacing: 3) {
                    Text(tag)
                    Button {
                        onRemoveTag(tag)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(String(format: String(localized: "Remove tag %@"), tag)))
                }
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Text.secondary)
                .padding(.horizontal, AppTheme.Spacing.s)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppTheme.Surface.card))
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            if transcription.enhancedText != nil {
                Picker("", selection: $selectedTab) {
                    ForEach(TranscriptionTab.allCases, id: \.self) { tab in
                        Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            // No nested ScrollView: long transcripts extend the row and scroll with the list,
            // so a trackpad gesture over a transcript no longer traps the scroll.
            MarkdownContentView(
                displayText,
                fontSize: 14,
                foregroundColor: AppTheme.Text.primary
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .hoverCopyButton(textToCopy: displayText)

            tagEditor

            if let audioURL {
                Divider()
                AudioPlayerView(url: audioURL, transcription: transcription, onInfoTap: onShowInfo)
                    .padding(.vertical, AppTheme.Spacing.xs)
            } else {
                HStack {
                    Spacer()
                    Button(action: onShowInfo) {
                        Image(systemName: "info.circle")
                            .font(AppTheme.Typography.label)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("View details")
                    .accessibilityLabel("View details")
                }
            }
        }
    }

    @ViewBuilder
    private var tagEditor: some View {
        if isAddingTag {
            TextField("Tag name", text: $draftTag)
                .textFieldStyle(.roundedBorder)
                .font(AppTheme.Typography.caption)
                .frame(maxWidth: 180)
                .focused($isTagFieldFocused)
                .onSubmit(commitTag)
                .onExitCommand(perform: cancelTag)
                .task { isTagFieldFocused = true }
        } else {
            Button {
                isAddingTag = true
            } label: {
                Label("Add Tag", systemImage: "tag")
                    .font(AppTheme.Typography.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func commitTag() {
        onAddTag(draftTag)
        draftTag = ""
        isAddingTag = false
    }

    private func cancelTag() {
        draftTag = ""
        isAddingTag = false
    }
}
