import AppKit
import SwiftData
import SwiftUI

/// ⌘K launcher over destinations, modes and recent transcripts.
struct CommandPaletteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MainWindowNavigation.self) private var navigation
    private let modeManager = ModeManager.shared

    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var highlightedIndex = 0
    @State private var recentTranscriptions: [Transcription] = []
    @FocusState private var isFieldFocused: Bool

    private static let maxResults = 30
    private static let transcriptFetchLimit = 40

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
        .frame(width: 560)
        .frame(maxHeight: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.panel, style: .continuous)
                .strokeBorder(AppTheme.Border.card, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
        .task {
            isFieldFocused = true
            await loadRecentTranscriptions()
        }
        .onChange(of: query) {
            highlightedIndex = 0
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search commands, modes, and transcripts", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($isFieldFocused)
                .onSubmit(activateHighlighted)
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppTheme.Spacing.l)
        .padding(.vertical, AppTheme.Spacing.m)
    }

    // MARK: - Results

    private var results: [CommandPaletteItem] {
        Array(CommandPaletteMatcher.rank(allItems, query: query).prefix(Self.maxResults))
    }

    @ViewBuilder
    private var resultsList: some View {
        let results = self.results

        if results.isEmpty {
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1, pinnedViews: .sectionHeaders) {
                        ForEach(sections(of: results)) { section in
                            paletteSection(section, in: results)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.xs)
                }
                .onChange(of: highlightedIndex) {
                    scrollToHighlighted(proxy, in: results)
                }
            }
        }
    }

    private func paletteSection(_ section: PaletteSection, in results: [CommandPaletteItem]) -> some View {
        Section {
            ForEach(section.items) { item in
                paletteRow(item, in: results)
            }
        } header: {
            Text(section.title)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.Spacing.l)
                .padding(.top, AppTheme.Spacing.s)
                .padding(.bottom, AppTheme.Spacing.xxs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
        }
    }

    private func paletteRow(_ item: CommandPaletteItem, in results: [CommandPaletteItem]) -> some View {
        let index = results.firstIndex { $0.id == item.id } ?? 0

        return CommandPaletteRow(item: item, isHighlighted: index == highlightedIndex)
            .id(item.id)
            .contentShape(Rectangle())
            .onTapGesture { activate(item) }
            .onHover { hovering in
                if hovering { highlightedIndex = index }
            }
    }

    private func scrollToHighlighted(_ proxy: ScrollViewProxy, in results: [CommandPaletteItem]) {
        guard results.indices.contains(highlightedIndex) else { return }
        withAnimation(AppTheme.Motion.micro) {
            proxy.scrollTo(results[highlightedIndex].id, anchor: .center)
        }
    }

    private struct PaletteSection: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let items: [CommandPaletteItem]
    }

    /// Groups results while preserving the ranked order — the first appearance of a section
    /// determines where that section sits.
    private func sections(of results: [CommandPaletteItem]) -> [PaletteSection] {
        var order: [Int] = []
        var buckets: [Int: [CommandPaletteItem]] = [:]
        var titles: [Int: LocalizedStringKey] = [:]

        for item in results {
            let rank = item.kind.rank
            if buckets[rank] == nil {
                order.append(rank)
                titles[rank] = item.kind.sectionTitle
            }
            buckets[rank, default: []].append(item)
        }

        return order.compactMap { rank in
            guard let items = buckets[rank], let title = titles[rank] else { return nil }
            return PaletteSection(id: rank, title: title, items: items)
        }
    }

    // MARK: - Items

    private var allItems: [CommandPaletteItem] {
        destinationItems + actionItems + modeItems + transcriptItems
    }

    private var destinationItems: [CommandPaletteItem] {
        ViewType.allCases.map { viewType in
            CommandPaletteItem(
                id: "destination-\(viewType.rawValue)",
                kind: .destination(viewType),
                title: viewType.rawValue,
                subtitle: nil,
                icon: viewType.paletteIcon,
                tint: viewType.paletteTint
            ) {
                navigation.navigate(to: viewType)
            }
        }
    }

    private var actionItems: [CommandPaletteItem] {
        [
            CommandPaletteItem(
                id: "action-copy-system-info",
                kind: .action,
                title: String(localized: "Copy System Info"),
                subtitle: String(localized: "For bug reports"),
                icon: "doc.on.doc",
                tint: AppTheme.Sidebar.fallback
            ) {
                SystemInfoService.shared.copySystemInfoToClipboard()
            }
        ]
    }

    private var modeItems: [CommandPaletteItem] {
        modeManager.enabledConfigurations.map { config in
            CommandPaletteItem(
                id: "mode-\(config.id.uuidString)",
                kind: .mode(config),
                title: config.name,
                subtitle: String(localized: "Mode"),
                icon: "sparkles.square.fill.on.square",
                tint: AppTheme.Sidebar.modes
            ) {
                modeManager.setActiveConfiguration(config)
            }
        }
    }

    private var transcriptItems: [CommandPaletteItem] {
        recentTranscriptions.map { transcription in
            let text = transcription.displayText.trimmingCharacters(in: .whitespacesAndNewlines)

            return CommandPaletteItem(
                id: "transcript-\(transcription.id.uuidString)",
                kind: .transcript(transcription),
                title: String(text.prefix(90)),
                subtitle: transcription.timestamp.formatted(
                    .dateTime.month(.abbreviated).day().hour().minute()
                ),
                icon: "text.quote",
                tint: AppTheme.Sidebar.history
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcription.displayText, forType: .string)
                NotificationManager.shared.showNotification(
                    title: String(localized: "Transcript copied"),
                    type: .success
                )
            }
        }
    }

    @MainActor
    private func loadRecentTranscriptions() async {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = Self.transcriptFetchLimit

        recentTranscriptions = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Interaction

    private func moveHighlight(by offset: Int) -> KeyPress.Result {
        let count = results.count
        guard count > 0 else { return .ignored }
        highlightedIndex = (highlightedIndex + offset + count) % count
        return .handled
    }

    private func activateHighlighted() {
        let results = self.results
        guard results.indices.contains(highlightedIndex) else { return }
        activate(results[highlightedIndex])
    }

    private func activate(_ item: CommandPaletteItem) {
        item.perform()
        dismiss()
    }

    private func dismiss() {
        query = ""
        highlightedIndex = 0
        isPresented = false
    }
}

// MARK: - Row

private struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.tile, style: .continuous)
                    .fill(item.tint)

                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(AppTheme.Typography.label)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(AppTheme.Typography.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if isHighlighted {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, AppTheme.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .fill(isHighlighted ? AppTheme.Selection.fill : .clear)
        )
        .padding(.horizontal, AppTheme.Spacing.s)
    }
}

// MARK: - Destination presentation

extension ViewType {
    var paletteIcon: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .transcribeAudio: return "waveform.path"
        case .history: return "doc.text.fill"
        case .models: return "cpu"
        case .modes: return "sparkles.square.fill.on.square"
        case .audio: return "mic.fill"
        case .dictionary: return "text.book.closed.fill"
        case .settings: return "gearshape.fill"
        case .license: return "checkmark.seal.fill"
        }
    }

    var paletteTint: Color {
        switch self {
        case .dashboard: return AppTheme.Sidebar.dashboard
        case .modes: return AppTheme.Sidebar.modes
        case .models: return AppTheme.Sidebar.models
        case .audio: return AppTheme.Sidebar.audio
        case .dictionary: return AppTheme.Sidebar.dictionary
        case .history: return AppTheme.Sidebar.history
        case .transcribeAudio: return AppTheme.Sidebar.transcribeAudio
        case .settings: return AppTheme.Sidebar.fallback
        case .license: return AppTheme.Sidebar.license
        }
    }
}
