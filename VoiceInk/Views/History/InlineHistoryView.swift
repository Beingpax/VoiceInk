import SwiftData
import SwiftUI

// Which slice of transcriptions InlineHistoryView is browsing: everything (paginated), or
// just the golden eval set candidates (PRD.md item 1) — recordings that still have audio.
enum InlineHistoryMode: Hashable {
    case all
    case goldenEvalSet
}

struct InlineHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var engine: VoiceInkEngine
    @State private var searchText = ""
    @State private var expandedId: UUID?
    @State private var selectedTranscriptions: Set<Transcription> = []
    @State private var showDeleteConfirmation = false
    @State private var isPanelPresented = false
    @State private var panelMode: InlineHistoryPanelMode = .info
    @State private var panelTranscriptionId: UUID?
    @State private var displayedTranscriptions: [Transcription] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?
    @State private var isViewCurrentlyVisible = false

    @State private var historyMode: InlineHistoryMode = .all
    @State private var goldenEvalCandidates: [Transcription] = []
    @State private var goldenEvalSplitsByTranscriptionId: [UUID: GoldenEvalSplit] = [:]
    @State private var goldenEvalCounts = GoldenEvalSetService.SplitCounts(control: 0, train: 0, eval: 0)
    @State private var isShowingBaselineSheet = false
    @State private var isRunningBaseline = false
    @State private var baselineSummaries: [WERBaselineHarness.ModelSummary] = []
    @State private var baselineError: String?
    @State private var selectedBaselineModelNames: Set<String> = ["Large v3", "Parakeet V3"]

    private let exportService = VoiceInkCSVExportService()
    private let pageSize = 20

    @Query(Self.createLatestTranscriptionIndicatorDescriptor()) private var latestTranscriptionIndicator:
        [Transcription]

    private static func createLatestTranscriptionIndicatorDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private func cursorQueryDescriptor(after timestamp: Date? = nil) -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )

        if let timestamp = timestamp {
            if !searchText.isEmpty {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    (transcription.text.localizedStandardContains(searchText)
                        || (transcription.enhancedText?.localizedStandardContains(searchText) ?? false))
                        && transcription.timestamp < timestamp
                }
            } else {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.timestamp < timestamp
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.text.localizedStandardContains(searchText)
                    || (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }

        descriptor.fetchLimit = pageSize
        return descriptor
    }

    private var allSelected: Bool {
        !currentTranscriptions.isEmpty && currentTranscriptions.allSatisfy { selectedTranscriptions.contains($0) }
    }

    private var panelTranscription: Transcription? {
        guard let id = panelTranscriptionId else { return nil }
        return displayedTranscriptions.first { $0.id == id }
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

    private var currentTranscriptions: [Transcription] {
        historyMode == .goldenEvalSet ? goldenEvalCandidates : displayedTranscriptions
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            modeToggle

            if historyMode == .goldenEvalSet {
                goldenEvalToolbar
            }

            Divider()

            if currentTranscriptions.isEmpty && !isLoading {
                emptyStateView
            } else {
                cardListView
            }

            if !selectedTranscriptions.isEmpty {
                Divider()
                selectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTranscriptions.isEmpty)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sidePanel(
            isPresented: .init(
                get: { isPanelPresented },
                set: { newValue in
                    if !newValue { closePanel() }
                }
            )
        ) {
            panelContent
        }
        .sheet(isPresented: $isShowingBaselineSheet) {
            baselineEvaluationSheet
        }
        .alert("Delete Selected Items?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedTranscriptions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                String(
                    localized:
                        "This action cannot be undone. Are you sure you want to delete \(selectedTranscriptions.count) items?"
                ))
        }
        .onAppear {
            isViewCurrentlyVisible = true
            Task { await loadInitialContent() }
        }
        .onDisappear {
            isViewCurrentlyVisible = false
        }
        .onChange(of: searchText) { _, _ in
            Task {
                await resetPagination()
                await loadInitialContent()
            }
        }
        .onChange(of: historyMode) { _, newMode in
            if newMode == .goldenEvalSet {
                Task { await loadGoldenEvalCandidates() }
            }
        }
        .onChange(of: latestTranscriptionIndicator.first?.id) { oldId, newId in
            guard isViewCurrentlyVisible else { return }
            if newId != oldId {
                Task {
                    await resetPagination()
                    await loadInitialContent()
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search transcriptions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AppTheme.Surface.card)
            )
            .frame(maxWidth: .infinity)

            AppIconButton(
                systemName: "gearshape",
                help: "History settings",
                size: 30,
                iconSize: 13,
                cornerRadius: AppTheme.Radius.pill
            ) {
                openPanel(mode: .historySettings)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var modeToggle: some View {
        Picker("", selection: $historyMode) {
            Text("All").tag(InlineHistoryMode.all)
            Text("Golden Eval Set").tag(InlineHistoryMode.goldenEvalSet)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("history.modeToggle")
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    // Golden eval set toolbar (PRD.md items 1 & 5): split counts plus the WER baseline
    // trigger, folded into the real primary History screen rather than a separate window.
    private var goldenEvalToolbar: some View {
        HStack {
            Text("Control: \(goldenEvalCounts.control) · Train: \(goldenEvalCounts.train) · Eval: \(goldenEvalCounts.eval)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .accessibilityIdentifier("history.goldenEvalCounts")
            Spacer()
            Button("Run Baseline Evaluation") {
                isShowingBaselineSheet = true
            }
            .font(.system(size: 11))
            .disabled(goldenEvalCounts.eval == 0)
            .accessibilityIdentifier("history.runBaselineEvaluation")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            Text(String(format: String(localized: "%lld selected"), Int64(selectedTranscriptions.count)))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                openPanel(mode: .analysis)
            }) {
                Label("Analyze", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button(action: {
                exportService.exportTranscriptionsToCSV(transcriptions: Array(selectedTranscriptions))
            }) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button(action: { showDeleteConfirmation = true }) {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(AppTheme.Status.error.opacity(0.80))

            Divider()
                .frame(height: 16)

            if allSelected {
                Button("Deselect All") {
                    selectedTranscriptions.removeAll()
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            } else {
                Button("Select All") {
                    Task { await selectAllTranscriptions() }
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(
            AppTheme.Surface.window
                .shadow(color: Color.black.opacity(0.1), radius: 3, y: -2)
        )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(emptyStateTitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            Text(emptyStateSubtitle)
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.8))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if historyMode == .goldenEvalSet {
            return String(localized: "No candidates with audio yet")
        }
        return searchText.isEmpty
            ? String(localized: "No transcriptions yet") : String(localized: "No results found")
    }

    private var emptyStateSubtitle: String {
        if historyMode == .goldenEvalSet {
            return String(localized: "Recordings that still have their audio file on disk will appear here")
        }
        return searchText.isEmpty
            ? String(localized: "Your transcription history will appear here")
            : String(localized: "Try a different search term")
    }

    // MARK: - Card List

    private var cardListView: some View {
        ScrollViewReader { scrollProxy in
            Form {
                ForEach(currentTranscriptions) { transcription in
                    Section {
                        HistoryCardRow(
                            transcription: transcription,
                            isExpanded: expandedId == transcription.id,
                            isChecked: selectedTranscriptions.contains(transcription),
                            goldenEvalSplit: goldenEvalSplitsByTranscriptionId[transcription.id],
                            onToggleExpand: {
                                let isExpanding = expandedId != transcription.id
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedId = isExpanding ? transcription.id : nil
                                }
                                // Expanded content (audio player, golden eval editor) can be
                                // taller than the visible viewport — without this, newly
                                // revealed content like the "Mark Verified" button can end up
                                // clipped below the window's bottom edge.
                                if isExpanding {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            scrollProxy.scrollTo(transcription.id, anchor: .top)
                                        }
                                    }
                                }
                            },
                            onToggleCheck: { toggleSelection(transcription) },
                            onShowInfo: {
                                openPanel(mode: .info, transcriptionID: transcription.id)
                            }
                        )
                    }
                    .id(transcription.id)
                }

                if historyMode == .all && hasMoreContent {
                    Section {
                        Button(action: {
                            Task { await loadMoreContent() }
                        }) {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView().controlSize(.small)
                                }
                                Text(isLoading ? "Loading..." : "Load More")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Side Panel

    @ViewBuilder
    private var panelContent: some View {
        switch panelMode {
        case .info:
            infoPanelContent
        case .analysis:
            HistoryAnalysisPanelView(
                transcriptions: Array(selectedTranscriptions),
                onClose: {
                    closePanel()
                }
            )
            .id(selectedTranscriptions.count)
        case .historySettings:
            HistorySettingsPanel(onClose: closePanel)
        }
    }

    private var infoPanelContent: some View {
        VStack(spacing: 0) {
            AppPanelHeader(title: "Info", onClose: closePanel)

            if let transcription = panelTranscription {
                TranscriptionInfoPanel(transcription: transcription)
                    .id(transcription.id)
            } else {
                Spacer()
            }
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadInitialContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            lastTimestamp = nil
            let items = try modelContext.fetch(cursorQueryDescriptor())
            displayedTranscriptions = items
            lastTimestamp = items.last?.timestamp
            hasMoreContent = items.count == pageSize
        } catch {
            print("Error loading transcriptions: \(error)")
        }
    }

    @MainActor
    private func loadMoreContent() async {
        guard !isLoading, hasMoreContent, let lastTimestamp = lastTimestamp else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let newItems = try modelContext.fetch(cursorQueryDescriptor(after: lastTimestamp))
            displayedTranscriptions.append(contentsOf: newItems)
            self.lastTimestamp = newItems.last?.timestamp
            hasMoreContent = newItems.count == pageSize
        } catch {
            print("Error loading more transcriptions: \(error)")
        }
    }

    @MainActor
    private func resetPagination() {
        displayedTranscriptions = []
        lastTimestamp = nil
        hasMoreContent = true
        isLoading = false
    }

    // MARK: - Selection & Deletion

    private func toggleSelection(_ transcription: Transcription) {
        if selectedTranscriptions.contains(transcription) {
            selectedTranscriptions.remove(transcription)
        } else {
            selectedTranscriptions.insert(transcription)
        }
    }

    private func performDeletion(for transcription: Transcription) {
        if let urlString = transcription.audioFileURL,
            let url = URL(string: urlString),
            FileManager.default.fileExists(atPath: url.path)
        {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Error deleting audio file: \(error.localizedDescription)")
            }
        }

        if expandedId == transcription.id {
            expandedId = nil
        }
        if panelTranscriptionId == transcription.id {
            panelTranscriptionId = nil
            closePanel()
        }

        selectedTranscriptions.remove(transcription)
        modelContext.delete(transcription)
    }

    private func deleteSelectedTranscriptions() {
        for transcription in selectedTranscriptions {
            performDeletion(for: transcription)
        }
        selectedTranscriptions.removeAll()

        Task {
            do {
                try modelContext.save()
                NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
            } catch {
                print("Error saving deletion: \(error.localizedDescription)")
            }

            if historyMode == .goldenEvalSet {
                await loadGoldenEvalCandidates()
            } else {
                await loadInitialContent()
            }
        }
    }

    private func selectAllTranscriptions() async {
        guard historyMode == .all else {
            selectedTranscriptions = Set(goldenEvalCandidates)
            return
        }

        do {
            var allDescriptor = FetchDescriptor<Transcription>()

            if !searchText.isEmpty {
                allDescriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.text.localizedStandardContains(searchText)
                        || (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
                }
            }

            allDescriptor.propertiesToFetch = [\.id]
            let allTranscriptions = try modelContext.fetch(allDescriptor)
            let visibleIds = Set(displayedTranscriptions.map { $0.id })

            await MainActor.run {
                selectedTranscriptions = Set(displayedTranscriptions)

                for transcription in allTranscriptions {
                    if !visibleIds.contains(transcription.id) {
                        selectedTranscriptions.insert(transcription)
                    }
                }
            }
        } catch {
            print("Error selecting all transcriptions: \(error)")
        }
    }

    @MainActor
    private func loadGoldenEvalCandidates() async {
        do {
            let all = try modelContext.fetch(
                FetchDescriptor<Transcription>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))
            goldenEvalCandidates = all.filter { GoldenEvalSetService.hasAudioFile($0) }

            let entries = try modelContext.fetch(FetchDescriptor<GoldenEvalEntry>())
            goldenEvalSplitsByTranscriptionId = Dictionary(
                uniqueKeysWithValues: entries.map { ($0.transcriptionId, $0.split) })

            refreshGoldenEvalCounts()
        } catch {
            print("Error loading golden eval candidates: \(error)")
        }
    }

    private func refreshGoldenEvalCounts() {
        goldenEvalCounts = (try? GoldenEvalSetService.splitCounts(in: modelContext))
            ?? GoldenEvalSetService.SplitCounts(control: 0, train: 0, eval: 0)
    }

    private var baselineEvaluationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Baseline WER Evaluation")
                .font(.system(size: 15, weight: .semibold))

            Text(
                "Runs every held-out eval-split recording (\(goldenEvalCounts.eval)) through the selected models, scoring each against its verified ground truth. Only models that are already downloaded (or have an API key configured) are listed."
            )
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Models (downloaded / API key configured)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                ForEach(engine.transcriptionModelManager.usableModels, id: \.displayName) { model in
                    Toggle(
                        model.displayName,
                        isOn: Binding(
                            get: { selectedBaselineModelNames.contains(model.displayName) },
                            set: { isOn in
                                if isOn {
                                    selectedBaselineModelNames.insert(model.displayName)
                                } else {
                                    selectedBaselineModelNames.remove(model.displayName)
                                }
                            }
                        )
                    )
                    .font(.system(size: 12))
                }
            }
            .frame(maxHeight: 160)

            if isRunningBaseline {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Evaluating…")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            if let baselineError {
                Text(baselineError)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Status.error)
            }

            if !baselineSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(baselineSummaries, id: \.modelDisplayName) { summary in
                        HStack {
                            Text(summary.modelDisplayName)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(String(format: "%.1f%% WER", summary.meanWordErrorRate * 100))
                                .font(.system(size: 13, weight: .semibold))
                            Text("(\(summary.evaluatedCount) evaluated, \(summary.failedCount) failed)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                .fill(AppTheme.Surface.subtle)
                        )
                    }
                }
            }

            HStack {
                Button(baselineSummaries.isEmpty ? "Run Now" : "Run Again") {
                    runBaselineEvaluation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunningBaseline || selectedBaselineModelNames.isEmpty)

                Button("Close") {
                    isShowingBaselineSheet = false
                }
            }
        }
        .padding(20)
        .frame(minWidth: 480)
    }

    @MainActor
    private func runBaselineEvaluation() {
        baselineError = nil
        isRunningBaseline = true

        Task { @MainActor in
            defer { isRunningBaseline = false }

            do {
                let evalRawValue = GoldenEvalSplit.eval.rawValue
                let evalEntries = try modelContext.fetch(
                    FetchDescriptor<GoldenEvalEntry>(
                        predicate: #Predicate<GoldenEvalEntry> { $0.splitRawValue == evalRawValue }))

                var evalCandidates: [WERBaselineHarness.Candidate] = []
                for entry in evalEntries {
                    let transcriptionId = entry.transcriptionId
                    var descriptor = FetchDescriptor<Transcription>(
                        predicate: #Predicate<Transcription> { $0.id == transcriptionId })
                    descriptor.fetchLimit = 1
                    guard let transcription = try modelContext.fetch(descriptor).first,
                        let urlString = transcription.audioFileURL,
                        let url = URL(string: urlString)
                    else { continue }

                    evalCandidates.append(
                        WERBaselineHarness.Candidate(
                            entryId: entry.id, referenceText: entry.groundTruthText, audioURL: url))
                }

                guard !evalCandidates.isEmpty else {
                    baselineError = String(localized: "No eval-split entries with a valid audio file were found.")
                    return
                }

                let models = engine.transcriptionModelManager.usableModels.filter {
                    selectedBaselineModelNames.contains($0.displayName)
                }

                guard !models.isEmpty else {
                    baselineError = String(localized: "Select at least one model to evaluate.")
                    return
                }

                let transcriber = TranscriptionServiceRegistryTranscriber(registry: engine.serviceRegistry)
                let runLabel = "baseline-\(Int(Date().timeIntervalSince1970))"

                baselineSummaries = await WERBaselineHarness.run(
                    candidates: evalCandidates,
                    models: models,
                    runLabel: runLabel,
                    transcriber: transcriber,
                    in: modelContext
                )
            } catch {
                baselineError = String(localized: "Failed to run baseline evaluation.")
            }
        }
    }
}

private enum InlineHistoryPanelMode {
    case info
    case analysis
    case historySettings
}

// MARK: - History Card Row

private struct HistoryCardRow: View {
    let transcription: Transcription
    let isExpanded: Bool
    let isChecked: Bool
    var goldenEvalSplit: GoldenEvalSplit? = nil
    let onToggleExpand: () -> Void
    let onToggleCheck: () -> Void
    let onShowInfo: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: TranscriptionTab = .original
    @State private var groundTruthText: String = ""
    @State private var goldenEvalEntry: GoldenEvalEntry?
    @State private var goldenEvalErrorMessage: String?
    @State private var hasLoadedGoldenEvalEntry = false

    private var displayText: String {
        switch selectedTab {
        case .original:
            return transcription.text
        case .enhanced:
            return transcription.enhancedText ?? ""
        }
    }

    private var hasAudioFile: Bool {
        if let urlString = transcription.audioFileURL,
            let url = URL(string: urlString),
            FileManager.default.fileExists(atPath: url.path)
        {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { isChecked },
                        set: { _ in onToggleCheck() }
                    )
                )
                .toggleStyle(CircularCheckboxStyle())
                .labelsHidden()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(transcription.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        if transcription.flagged {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppTheme.Status.warningStrong)
                        }

                        if let goldenEvalSplit {
                            Text(splitLabel(goldenEvalSplit))
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(splitColor(goldenEvalSplit)))
                                .foregroundColor(.white)
                        }
                    }

                    if !isExpanded {
                        Text(transcription.enhancedText ?? transcription.text)
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .foregroundColor(.primary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            if isExpanded {
                expandedContent
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tabs
            if transcription.enhancedText != nil {
                HStack(spacing: 4) {
                    ForEach(TranscriptionTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(LocalizedStringKey(tab.rawValue))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? AppTheme.Surface.controlActive : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            ScrollView {
                MarkdownContentView(
                    displayText,
                    fontSize: 14,
                    foregroundColor: AppTheme.Text.primary
                )
            }
            .frame(maxHeight: 350)
            .hoverCopyButton(
                textToCopy: displayText, transcriptionId: transcription.id, telemetrySource: "hover_button")

            if hasAudioFile, let urlString = transcription.audioFileURL,
                let url = URL(string: urlString)
            {
                Divider()
                AudioPlayerView(url: url, transcription: transcription, onInfoTap: onShowInfo)
                    .padding(.vertical, 4)

                Divider()
                goldenEvalSetSection
            } else {
                HStack {
                    Spacer()
                    Button(action: onShowInfo) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("View details")
                }
            }
        }
        .onAppear {
            guard !hasLoadedGoldenEvalEntry else { return }
            hasLoadedGoldenEvalEntry = true
            loadGoldenEvalEntry()
        }
    }

    // Inline golden eval set panel (ADR-0009, PRD.md "Golden eval set / WER tooling UI
    // integration") — folded into InlineHistoryView's expandable row rather than a separate
    // window. No train/eval/control picker: GoldenEvalSetService.verify categorizes
    // automatically based on whether groundTruthText differs from VoiceInk's original transcript.
    private var goldenEvalSetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Golden Eval Set")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if let goldenEvalEntry {
                    Text(splitLabel(goldenEvalEntry.split))
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(splitColor(goldenEvalEntry.split)))
                        .foregroundColor(.white)
                }
            }

            Text("Ground truth (edit if VoiceInk got it wrong, then mark verified)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            TextEditor(text: $groundTruthText)
                .font(.system(size: 13))
                .frame(minHeight: 80)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .fill(AppTheme.Surface.materialCard)
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                .strokeBorder(AppTheme.Border.subtle, lineWidth: 1)
                        }
                )

            HStack {
                Button(goldenEvalEntry == nil ? "Mark Verified" : "Update") {
                    verifyGoldenEval()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("history.markVerified")

                if goldenEvalEntry != nil {
                    Button("Remove", role: .destructive) {
                        removeGoldenEval()
                    }
                    .controlSize(.small)
                }

                if let goldenEvalErrorMessage {
                    Text(goldenEvalErrorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Status.error)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func splitLabel(_ split: GoldenEvalSplit) -> String {
        switch split {
        case .control: return "Control"
        case .train: return "Train"
        case .eval: return "Eval"
        }
    }

    private func splitColor(_ split: GoldenEvalSplit) -> Color {
        switch split {
        case .control: return AppTheme.Data.purple
        case .train: return AppTheme.Status.infoStrong
        case .eval: return AppTheme.Status.positive
        }
    }

    private func loadGoldenEvalEntry() {
        goldenEvalErrorMessage = nil
        do {
            let entry = try GoldenEvalSetService.entry(for: transcription.id, in: modelContext)
            goldenEvalEntry = entry
            groundTruthText = entry?.groundTruthText ?? (transcription.enhancedText ?? transcription.text)
        } catch {
            goldenEvalErrorMessage = String(localized: "Failed to load golden eval entry")
        }
    }

    private func verifyGoldenEval() {
        do {
            goldenEvalEntry = try GoldenEvalSetService.verify(
                transcriptionId: transcription.id,
                originalText: transcription.enhancedText ?? transcription.text,
                groundTruthText: groundTruthText,
                in: modelContext
            )
            goldenEvalErrorMessage = nil
        } catch {
            goldenEvalErrorMessage = String(localized: "Failed to save golden eval entry")
        }
    }

    private func removeGoldenEval() {
        do {
            try GoldenEvalSetService.remove(transcriptionId: transcription.id, in: modelContext)
            goldenEvalEntry = nil
            goldenEvalErrorMessage = nil
        } catch {
            goldenEvalErrorMessage = String(localized: "Failed to remove golden eval entry")
        }
    }
}
