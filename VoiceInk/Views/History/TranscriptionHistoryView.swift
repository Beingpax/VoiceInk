import SwiftData
import SwiftUI

// Which slice of transcriptions the sidebar list is browsing: everything (paginated), or just
// the golden eval set candidates (PRD.md item 1) — recordings that still have audio on disk.
enum HistorySidebarMode: Hashable {
    case all
    case goldenEvalSet
}

struct TranscriptionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var engine: VoiceInkEngine
    @State private var searchText = ""
    @State private var selectedTranscription: Transcription?
    @State private var selectedTranscriptions: Set<Transcription> = []
    @State private var showDeleteConfirmation = false
    @State private var isViewCurrentlyVisible = false
    @State private var isAnalysisPanelPresented = false
    @State private var isLeftSidebarVisible = true
    @State private var isRightSidebarVisible = false
    @State private var leftSidebarWidth: CGFloat = 300
    @State private var displayedTranscriptions: [Transcription] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?

    @State private var sidebarMode: HistorySidebarMode = .all
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

    private func openAnalysisPanel() {
        isRightSidebarVisible = false
        isAnalysisPanelPresented = true
    }

    private func closeAnalysisPanel() {
        isAnalysisPanelPresented = false
    }

    private func openInfoPanel() {
        isAnalysisPanelPresented = false
        isRightSidebarVisible = true
    }

    private func closeInfoPanel() {
        isRightSidebarVisible = false
    }

    var body: some View {
        HStack(spacing: 0) {
            if isLeftSidebarVisible {
                leftSidebarView
                    .frame(width: leftSidebarWidth)
                    .transition(.move(edge: .leading))

                Divider()
            }

            centerPaneView
                .frame(maxWidth: .infinity)
        }
        .background(historyBackground)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { withAnimation { isLeftSidebarVisible.toggle() } }) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
            }

            ToolbarItemGroup(placement: .automatic) {
                Button(action: {
                    withAnimation {
                        isRightSidebarVisible ? closeInfoPanel() : openInfoPanel()
                    }
                }) {
                    Label("Toggle Inspector", systemImage: "sidebar.right")
                }
            }
        }
        .alert("Delete Selected Items?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedTranscriptions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = selectedTranscriptions.count
            Text(String(localized: "This action cannot be undone. Are you sure you want to delete \(count) items?"))
        }
        .sidePanel(
            isPresented: .init(
                get: { isRightSidebarVisible },
                set: { newValue in
                    if !newValue { closeInfoPanel() }
                }
            )
        ) {
            infoSidePanelView
        }
        .sidePanel(
            isPresented: .init(
                get: { isAnalysisPanelPresented },
                set: { newValue in
                    if !newValue { closeAnalysisPanel() }
                }
            )
        ) {
            HistoryAnalysisPanelView(
                transcriptions: Array(selectedTranscriptions),
                onClose: closeAnalysisPanel
            )
            .id(selectedTranscriptions.count)
        }
        .onAppear {
            isViewCurrentlyVisible = true
            Task {
                await loadInitialContent()
            }
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

    private var historyBackground: some View {
        SidePanelBackground()
            .ignoresSafeArea(.container, edges: .top)
    }

    private var sidebarMaterialBackground: some View {
        VisualEffectView(
            material: .sidebar,
            blendingMode: .behindWindow
        )
        .ignoresSafeArea(.container, edges: .top)
    }

    private var detailMaterialBackground: some View {
        SidePanelBackground()
            .ignoresSafeArea(.container, edges: .top)
    }

    private var leftSidebarView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search transcriptions", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(AppTheme.Surface.subtle)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .strokeBorder(AppTheme.Border.tint, lineWidth: 1)
                    }
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Picker("", selection: $sidebarMode) {
                Text("All").tag(HistorySidebarMode.all)
                Text("Golden Eval Set").tag(HistorySidebarMode.goldenEvalSet)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .onChange(of: sidebarMode) { _, newMode in
                if newMode == .goldenEvalSet {
                    Task { await loadGoldenEvalCandidates() }
                }
            }

            if sidebarMode == .goldenEvalSet {
                goldenEvalToolbar
            }

            Divider()

            ZStack(alignment: .bottom) {
                if currentTranscriptions.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(sidebarMode == .goldenEvalSet ? "No candidates with audio yet" : "No transcriptions")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(currentTranscriptions) { transcription in
                                TranscriptionListItem(
                                    transcription: transcription,
                                    isSelected: selectedTranscription == transcription,
                                    isChecked: selectedTranscriptions.contains(transcription),
                                    onSelect: { selectedTranscription = transcription },
                                    onToggleCheck: { toggleSelection(transcription) },
                                    goldenEvalSplit: goldenEvalSplitsByTranscriptionId[transcription.id]
                                )
                            }

                            if sidebarMode == .all && hasMoreContent {
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
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                .disabled(isLoading)
                            }
                        }
                        .padding(8)
                        .padding(.bottom, 50)
                    }
                }

                if sidebarMode == .all && !displayedTranscriptions.isEmpty {
                    selectionToolbar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(sidebarMaterialBackground)
        .sheet(isPresented: $isShowingBaselineSheet) {
            baselineEvaluationSheet
        }
    }

    private var currentTranscriptions: [Transcription] {
        sidebarMode == .goldenEvalSet ? goldenEvalCandidates : displayedTranscriptions
    }

    // Golden eval set section toolbar (PRD.md items 1 & 5): split counts plus the WER
    // baseline trigger, folded in here instead of a separate window's own toolbar.
    private var goldenEvalToolbar: some View {
        HStack {
            Text("Control: \(goldenEvalCounts.control) · Train: \(goldenEvalCounts.train) · Eval: \(goldenEvalCounts.eval)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Button("Run Baseline Evaluation") {
                isShowingBaselineSheet = true
            }
            .font(.system(size: 11))
            .disabled(goldenEvalCounts.eval == 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var centerPaneView: some View {
        Group {
            if let transcription = selectedTranscription {
                TranscriptionDetailView(transcription: transcription, onInfoTap: openInfoPanel)
                    .id(transcription.id)
            } else {
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(minHeight: 40)

                        VStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text("No Selection")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Select a transcription to view details")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }

                        HistoryShortcutTipView()
                            .padding(.horizontal, 24)

                        Spacer()
                            .frame(minHeight: 40)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 600)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(detailMaterialBackground)
    }

    private var infoSidePanelView: some View {
        VStack(spacing: 0) {
            AppPanelHeader(title: "Info", onClose: closeInfoPanel)

            if let transcription = selectedTranscription {
                TranscriptionInfoPanel(transcription: transcription)
                    .id(transcription.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Metadata")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var allSelected: Bool {
        !displayedTranscriptions.isEmpty && displayedTranscriptions.allSatisfy { selectedTranscriptions.contains($0) }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            if allSelected {
                Button("Deselect All") {
                    selectedTranscriptions.removeAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            } else {
                Button("Select All") {
                    Task { await selectAllTranscriptions() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            }

            if !selectedTranscriptions.isEmpty {
                Divider()
                    .frame(height: 16)

                Button(action: {
                    openAnalysisPanel()
                }) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Analyze")

                Button(action: {
                    exportService.exportTranscriptionsToCSV(transcriptions: Array(selectedTranscriptions))
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Export")

                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }

            Spacer()

            if !selectedTranscriptions.isEmpty {
                Text(String(format: String(localized: "%lld selected"), Int64(selectedTranscriptions.count)))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .withinWindow
            )
            .shadow(color: Color.black.opacity(0.15), radius: 3, y: -2)
        )
    }

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

        if selectedTranscription == transcription {
            selectedTranscription = nil
        }

        selectedTranscriptions.remove(transcription)
        TelemetryService.captureTranscriptionDiscarded(transcriptionId: transcription.id, reason: "deleted_from_history")
        modelContext.delete(transcription)
    }

    private func saveAndReload() async {
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
            await loadInitialContent()
        } catch {
            print("Error saving deletion: \(error.localizedDescription)")
            await loadInitialContent()
        }
    }

    private func deleteSelectedTranscriptions() {
        for transcription in selectedTranscriptions {
            performDeletion(for: transcription)
        }
        selectedTranscriptions.removeAll()

        Task {
            await saveAndReload()
        }
    }

    private func toggleSelection(_ transcription: Transcription) {
        if selectedTranscriptions.contains(transcription) {
            selectedTranscriptions.remove(transcription)
        } else {
            selectedTranscriptions.insert(transcription)
        }
    }

    private func selectAllTranscriptions() async {
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
