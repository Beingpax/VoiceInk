import SwiftUI
import SwiftData

struct TranscriptionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedTranscription: Transcription?
    @State private var selectedTranscriptions: Set<Transcription> = []
    @State private var showDeleteConfirmation = false
    @State private var isViewCurrentlyVisible = false
    @State private var showAnalysisView = false
    @State private var isLeftSidebarVisible = true
    @State private var isRightSidebarVisible = true
    @State private var leftSidebarWidth: CGFloat = 260
    @State private var rightSidebarWidth: CGFloat = 260
    @State private var displayedTranscriptions: [Transcription] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?
    @State private var selectedPowerMode: String? = nil
    @State private var selectedModelName: String? = nil
    @State private var availablePowerModes: [String] = []
    @State private var availableModelNames: [String] = []

    private let exportService = VoiceInkCSVExportService()
    private let minSidebarWidth: CGFloat = 200
    private let maxSidebarWidth: CGFloat = 350
    private let pageSize = 20

    private var filteredTranscriptions: [Transcription] {
        displayedTranscriptions.filter { t in
            if let mode = selectedPowerMode, t.powerModeName != mode { return false }
            if let model = selectedModelName, t.transcriptionModelName != model { return false }
            return true
        }
    }

    private var groupedTranscriptions: [(header: String, transcriptions: [Transcription])] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
              let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start
        else { return [("All", filteredTranscriptions)] }

        var today: [Transcription] = []
        var yesterday: [Transcription] = []
        var thisWeek: [Transcription] = []
        var thisMonth: [Transcription] = []
        var older: [Transcription] = []

        for t in filteredTranscriptions {
            if t.timestamp >= startOfToday {
                today.append(t)
            } else if t.timestamp >= startOfYesterday {
                yesterday.append(t)
            } else if t.timestamp >= startOfWeek {
                thisWeek.append(t)
            } else if t.timestamp >= startOfMonth {
                thisMonth.append(t)
            } else {
                older.append(t)
            }
        }

        var groups: [(header: String, transcriptions: [Transcription])] = []
        if !today.isEmpty { groups.append(("Today", today)) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { groups.append(("This Week", thisWeek)) }
        if !thisMonth.isEmpty { groups.append(("This Month", thisMonth)) }
        if !older.isEmpty { groups.append(("Older", older)) }
        return groups
    }

    @Query(Self.createLatestTranscriptionIndicatorDescriptor()) private var latestTranscriptionIndicator: [Transcription]

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
                    (transcription.text.localizedStandardContains(searchText) ||
                    (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                    transcription.timestamp < timestamp
                }
            } else {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.timestamp < timestamp
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.text.localizedStandardContains(searchText) ||
                (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }
        
        descriptor.fetchLimit = pageSize
        return descriptor
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if isLeftSidebarVisible {
                leftSidebarView
                    .frame(
                        minWidth: minSidebarWidth,
                        idealWidth: leftSidebarWidth,
                        maxWidth: maxSidebarWidth
                    )
                    .transition(.move(edge: .leading))

                Divider()
            }

            centerPaneView
                .frame(maxWidth: .infinity)

            if isRightSidebarVisible {
                Divider()

                rightSidebarView
                    .frame(
                        minWidth: minSidebarWidth,
                        idealWidth: rightSidebarWidth,
                        maxWidth: maxSidebarWidth
                    )
                    .transition(.move(edge: .trailing))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { withAnimation { isLeftSidebarVisible.toggle() } }) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
            }

            ToolbarItemGroup(placement: .automatic) {
                Button(action: { withAnimation { isRightSidebarVisible.toggle() } }) {
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
            Text("This action cannot be undone. Are you sure you want to delete \(selectedTranscriptions.count) item\(selectedTranscriptions.count == 1 ? "" : "s")?")
        }
        .sheet(isPresented: $showAnalysisView) {
            if !selectedTranscriptions.isEmpty {
                PerformanceAnalysisView(transcriptions: Array(selectedTranscriptions))
            }
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
            )
            .padding(12)

            if !availablePowerModes.isEmpty || !availableModelNames.isEmpty {
                HStack(spacing: 6) {
                    if !availablePowerModes.isEmpty {
                        Menu {
                            Button("All Power Modes") { selectedPowerMode = nil }
                            Divider()
                            ForEach(availablePowerModes, id: \.self) { mode in
                                Button(mode) { selectedPowerMode = mode }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedPowerMode ?? "Power Mode")
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(.system(size: 11, weight: selectedPowerMode != nil ? .semibold : .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selectedPowerMode != nil ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !availableModelNames.isEmpty {
                        Menu {
                            Button("All Models") { selectedModelName = nil }
                            Divider()
                            ForEach(availableModelNames, id: \.self) { model in
                                Button(model) { selectedModelName = model }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedModelName ?? "Model")
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(.system(size: 11, weight: selectedModelName != nil ? .semibold : .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selectedModelName != nil ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if selectedPowerMode != nil || selectedModelName != nil {
                        Button {
                            selectedPowerMode = nil
                            selectedModelName = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            Divider()

            ZStack(alignment: .bottom) {
                if filteredTranscriptions.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No transcriptions")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8, pinnedViews: .sectionHeaders) {
                            ForEach(groupedTranscriptions, id: \.header) { group in
                                Section {
                                    ForEach(group.transcriptions) { transcription in
                                        TranscriptionListItem(
                                            transcription: transcription,
                                            isSelected: selectedTranscription == transcription,
                                            isChecked: selectedTranscriptions.contains(transcription),
                                            onSelect: { selectedTranscription = transcription },
                                            onToggleCheck: { toggleSelection(transcription) }
                                        )
                                    }
                                } header: {
                                    Text(group.header)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 4)
                                        .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
                                }
                            }

                            if hasMoreContent {
                                if isLoading {
                                    HStack {
                                        Spacer()
                                        ProgressView().controlSize(.small)
                                        Spacer()
                                    }
                                    .padding(.vertical, 10)
                                } else {
                                    Color.clear
                                        .frame(height: 1)
                                        .onAppear {
                                            Task { await loadMoreContent() }
                                        }
                                }
                            }
                        }
                        .padding(8)
                        .padding(.bottom, 50)
                    }
                }

                if !filteredTranscriptions.isEmpty {
                    selectionToolbar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var centerPaneView: some View {
        Group {
            if let transcription = selectedTranscription {
                TranscriptionDetailView(transcription: transcription)
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
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }

    private var rightSidebarView: some View {
        Group {
            if let transcription = selectedTranscription {
                TranscriptionMetadataView(transcription: transcription)
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
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            if selectedTranscriptions.isEmpty {
                Button("Select All") {
                    Task { await selectAllTranscriptions() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            } else {
                Button("Deselect All") {
                    selectedTranscriptions.removeAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

                Divider()
                    .frame(height: 16)

                Button(action: { showAnalysisView = true }) {
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
                Text("\(selectedTranscriptions.count) selected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color(NSColor.windowBackgroundColor)
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
            updateAvailableFilterOptions()
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
            updateAvailableFilterOptions()
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
        availablePowerModes = []
        availableModelNames = []
    }

    private func updateAvailableFilterOptions() {
        var modes = Set(availablePowerModes)
        var models = Set(availableModelNames)
        for t in displayedTranscriptions {
            if let m = t.powerModeName, !m.isEmpty { modes.insert(m) }
            if let m = t.transcriptionModelName, !m.isEmpty { models.insert(m) }
        }
        availablePowerModes = modes.sorted()
        availableModelNames = models.sorted()
    }

    private func performDeletion(for transcription: Transcription) {
        if let urlString = transcription.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
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

    private func deleteTranscription(_ transcription: Transcription) {
        performDeletion(for: transcription)
        Task {
            await saveAndReload()
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
                    transcription.text.localizedStandardContains(searchText) ||
                    (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
                }
            }

            let allTranscriptions = try modelContext.fetch(allDescriptor)

            let filtered = allTranscriptions.filter { t in
                if let mode = selectedPowerMode, t.powerModeName != mode { return false }
                if let model = selectedModelName, t.transcriptionModelName != model { return false }
                return true
            }

            await MainActor.run {
                selectedTranscriptions = Set(filtered)
            }
        } catch {
            print("Error selecting all transcriptions: \(error)")
        }
    }
}
