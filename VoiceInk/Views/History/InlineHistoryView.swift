import SwiftUI
import SwiftData
import AVFoundation

struct InlineHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedTranscriptions: Set<Transcription> = []
    @State private var showDeleteConfirmation = false
    
    // Sidebar list filters
    @State private var selectedFilter: String = "All"
    
    // Split screen detail view state
    @State private var selectedDetailTranscription: Transcription? = nil
    
    @State private var displayedTranscriptions: [Transcription] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?
    @State private var isViewCurrentlyVisible = false
    
    @State private var isPanelPresented = false
    @State private var panelMode: PanelMode = .info
    @State private var panelTranscriptionId: UUID?

    private let exportService = VoiceInkCSVExportService()
    private let pageSize = 20

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

        let isSemanticSearch = UserDefaults.standard.bool(forKey: "superchargeSemanticHistorySearch")

        if let timestamp = timestamp {
            if !searchText.isEmpty && !isSemanticSearch {
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
        } else if !searchText.isEmpty && !isSemanticSearch {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.text.localizedStandardContains(searchText) ||
                (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }

        descriptor.fetchLimit = pageSize
        return descriptor
    }

    private var allSelected: Bool {
        !displayedTranscriptions.isEmpty && displayedTranscriptions.allSatisfy { selectedTranscriptions.contains($0) }
    }

    private var filteredTranscriptions: [Transcription] {
        let items = displayedTranscriptions.filter { transcription in
            let status = transcription.transcriptionStatus ?? "completed"
            switch selectedFilter {
            case "Completed":
                return status == "completed"
            case "Processing":
                return status == "pending"
            case "Canceled":
                return status == "canceled"
            case "Failed":
                return status == "failed"
            default:
                return true
            }
        }
        
        if UserDefaults.standard.bool(forKey: "superchargeSemanticHistorySearch") && !searchText.isEmpty {
            return items.filter { SemanticSearchScorer.matches(searchText: searchText, text: $0.text + " " + ($0.enhancedText ?? "")) }
        } else {
            return items
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Sidebar Pane
            VStack(spacing: 0) {
                // Search box
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search transcriptions...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Category capsules
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["All", "Completed", "Processing", "Canceled", "Failed"], id: \.self) { category in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedFilter = category
                                }
                            } label: {
                                Text(category)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(selectedFilter == category ? .white : Color(red: 0.12, green: 0.12, blue: 0.18).opacity(0.6))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedFilter == category ? Color(red: 0.36, green: 0.28, blue: 0.88) : Color.white)
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(selectedFilter == category ? Color.clear : Color.primary.opacity(0.04), lineWidth: 1)
                                    )
                                    .shadow(color: selectedFilter == category ? Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.15) : Color.clear, radius: 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider().opacity(0.5)

                // List View
                if filteredTranscriptions.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("No items found")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredTranscriptions) { transcription in
                                HistorySidebarRowCard(
                                    transcription: transcription,
                                    isSelected: selectedDetailTranscription?.id == transcription.id,
                                    isChecked: selectedTranscriptions.contains(transcription),
                                    onSelect: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedDetailTranscription = transcription
                                        }
                                    },
                                    onCheckToggle: {
                                        toggleSelection(transcription)
                                    }
                                )
                            }

                            if hasMoreContent {
                                Button {
                                    Task { await loadMoreContent() }
                                } label: {
                                    HStack {
                                        if isLoading {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Text("Load More")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .disabled(isLoading)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }

                // Sidebar Footer (Selection & Actions)
                if !selectedTranscriptions.isEmpty {
                    VStack(spacing: 8) {
                        Divider().opacity(0.5)
                        HStack(spacing: 12) {
                            Text("\(selectedTranscriptions.count) selected")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                exportService.exportTranscriptionsToCSV(transcriptions: Array(selectedTranscriptions))
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Export selected CSV")

                            Button {
                                showDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help("Delete selected items")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white)
                    }
                }
            }
            .frame(width: 320)
            .background(Color(red: 0.97, green: 0.97, blue: 0.98))

            VerticalDivider()

            // MARK: - Right Detail Pane
            Group {
                if let transcription = selectedDetailTranscription {
                    TranscriptionDetailsPane(
                        transcription: transcription,
                        onDelete: {
                            performDeletion(for: transcription)
                            selectedDetailTranscription = displayedTranscriptions.first
                        }
                    )
                    .id(transcription.id)
                } else {
                    // Beautiful blank placeholder
                    VStack(spacing: 16) {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.04))
                                .frame(width: 120, height: 120)
                            Circle()
                                .stroke(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .frame(width: 90, height: 90)
                            Image(systemName: "waveform.and.mic")
                                .font(.system(size: 36))
                                .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.5))
                        }
                        
                        Text("No Transcription Selected")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                        
                        Text("Select an audio dictation item from the history list to preview the continuous waveform, review text results, summaries, and diagnostic metadata.")
                            .font(.system(size: 12))
                            .foregroundColor(Color.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Delete Selected Items?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedTranscriptions()
                selectedDetailTranscription = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Are you sure you want to delete \(selectedTranscriptions.count) item\(selectedTranscriptions.count == 1 ? "" : "s")?")
        }
        .onAppear {
            isViewCurrentlyVisible = true
            Task {
                await loadInitialContent()
                if selectedDetailTranscription == nil {
                    selectedDetailTranscription = displayedTranscriptions.first
                }
            }
        }
        .onDisappear {
            isViewCurrentlyVisible = false
        }
        .onChange(of: searchText) { _, _ in
            Task {
                await resetPagination()
                await loadInitialContent()
                selectedDetailTranscription = displayedTranscriptions.first
            }
        }
        .onChange(of: latestTranscriptionIndicator.first?.id) { oldId, newId in
            guard isViewCurrentlyVisible else { return }
            if newId != oldId {
                Task {
                    await resetPagination()
                    await loadInitialContent()
                    if selectedDetailTranscription == nil {
                        selectedDetailTranscription = displayedTranscriptions.first
                    }
                }
            }
        }
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
           FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Error deleting audio file: \(error.localizedDescription)")
            }
        }

        if panelTranscriptionId == transcription.id {
            panelTranscriptionId = nil
            isPanelPresented = false
        }

        selectedTranscriptions.remove(transcription)
        modelContext.delete(transcription)
        
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
        } catch {
            print("Error saving delete: \(error)")
        }
    }

    private func deleteSelectedTranscriptions() {
        for transcription in selectedTranscriptions {
            performDeletion(for: transcription)
        }
        selectedTranscriptions.removeAll()

        Task {
            await loadInitialContent()
        }
    }
}

// MARK: - Vertical Divider

struct VerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }
}

// MARK: - History Sidebar Row Card

private struct HistorySidebarRowCard: View {
    let transcription: Transcription
    let isSelected: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onCheckToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox on the left
            Toggle("", isOn: Binding(
                get: { isChecked },
                set: { _ in onCheckToggle() }
            ))
            .toggleStyle(CircularCheckboxStyle())
            .labelsHidden()
            .padding(.leading, 12)

            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transcription.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Duration indicator
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(transcription.duration.formatTiming())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.04))
                    .cornerRadius(4)
                }

                Text(transcription.enhancedText ?? transcription.text)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .foregroundColor(isSelected ? Color(red: 0.12, green: 0.12, blue: 0.18) : Color(red: 0.12, green: 0.12, blue: 0.18).opacity(0.8))
                
                // Status tag
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(statusText)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(statusColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.08))
                .cornerRadius(4)
            }
            .padding(.vertical, 10)
            .padding(.trailing, 12)
        }
        .background(isSelected ? Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.06) : Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.3) : Color.primary.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: isSelected ? Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.04) : Color.black.opacity(0.01), radius: 3, x: 0, y: 1)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            if hovering && UserDefaults.standard.bool(forKey: "superchargeTactileHapticScrubbing") {
                #if canImport(AppKit)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                #endif
            }
        }
    }

    private var statusColor: Color {
        let rawStatus = transcription.transcriptionStatus ?? "completed"
        switch rawStatus {
        case "completed": return .green
        case "pending": return .orange
        case "canceled": return .gray
        case "failed": return .red
        default: return .green
        }
    }

    private var statusText: String {
        let rawStatus = transcription.transcriptionStatus ?? "completed"
        switch rawStatus {
        case "completed": return "Completed"
        case "pending": return "Processing"
        case "canceled": return "Canceled"
        case "failed": return "Failed"
        default: return "Completed"
        }
    }
}

// MARK: - Transcription Details Pane (Right Screen)

struct TranscriptionDetailsPane: View {
    let transcription: Transcription
    let onDelete: () -> Void

    @State private var activeTab: String = "Transcript"
    @State private var selectedTab: TranscriptionTab = .original

    private var hasAudioFile: Bool {
        if let urlString = transcription.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transcription.timestamp, format: .dateTime.month(.wide).day().year().hour().minute().second())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(statusColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.08))
                    .cornerRadius(6)
                }
                
                Spacer()
                
                // Header Actions
                HStack(spacing: 8) {
                    Button {
                        let text = transcription.enhancedText ?? transcription.text
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(text, forType: .string)
                    } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.08))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(Color.white)
            
            Divider().opacity(0.5)

            ScrollView {
                VStack(spacing: 20) {
                    // Metrics Row
                    HStack(spacing: 12) {
                        // Card 1: Duration
                        MetricTileCard(
                            icon: "clock.fill",
                            title: "Duration",
                            value: transcription.duration.formatTiming(),
                            accentColor: .blue
                        )
                        
                        // Card 2: AI Model
                        MetricTileCard(
                            icon: "cpu.fill",
                            title: "Speech Model",
                            value: transcription.transcriptionModelName ?? "Whisper Local",
                            accentColor: .purple
                        )
                        
                        // Card 3: AI Enhancement
                        MetricTileCard(
                            icon: "bolt.shield.fill",
                            title: "AI Enhancer",
                            value: transcription.aiEnhancementModelName ?? "None",
                            accentColor: .orange
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Integrated Media Controller Waveform Box
                    if hasAudioFile, let urlString = transcription.audioFileURL, let url = URL(string: urlString) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Continuous Waveform Preview")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                .padding(.horizontal, 4)
                            
                            AudioPlayerView(url: url, transcription: transcription, onInfoTap: {})
                                .padding(12)
                                .background(Color(red: 0.98, green: 0.98, blue: 0.99))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 20)
                    }

                    // Customizable Detailed Tabs
                    VStack(alignment: .leading, spacing: 14) {
                        // Tabs selector bar
                        HStack(spacing: 16) {
                            ForEach(["Transcript", "System Metadata", "AI Prompt Context"], id: \.self) { tab in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        activeTab = tab
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        Text(tab)
                                            .font(.system(size: 13, weight: activeTab == tab ? .bold : .semibold))
                                            .foregroundColor(activeTab == tab ? Color(red: 0.36, green: 0.28, blue: 0.88) : Color.secondary)
                                        
                                        Rectangle()
                                            .fill(activeTab == tab ? Color(red: 0.36, green: 0.28, blue: 0.88) : Color.clear)
                                            .frame(height: 2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                        .border(width: 1, edges: [.bottom], color: Color.primary.opacity(0.04))

                        // Tab Contents
                        if activeTab == "Transcript" {
                            VStack(alignment: .leading, spacing: 14) {
                                if transcription.enhancedText != nil {
                                    // Original/Enhanced Picker
                                    HStack {
                                        ForEach(TranscriptionTab.allCases, id: \.self) { tab in
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.15)) {
                                                    selectedTab = tab
                                                }
                                            } label: {
                                                Text(tab.rawValue)
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(selectedTab == tab ? .white : Color(red: 0.36, green: 0.28, blue: 0.88))
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 5)
                                                    .background(selectedTab == tab ? Color(red: 0.36, green: 0.28, blue: 0.88) : Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.06))
                                                    .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }

                                Text(selectedTab == .original ? transcription.text : (transcription.enhancedText ?? ""))
                                    .font(.system(size: 13, design: .serif))
                                    .lineSpacing(6)
                                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                                    .textSelection(.enabled)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(red: 0.98, green: 0.98, blue: 0.99))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                                    )
                            }
                        } else if activeTab == "System Metadata" {
                            VStack(spacing: 12) {
                                MetadataRow(label: "Transcription Duration", value: transcription.transcriptionDuration != nil ? String(format: "%.2fs", transcription.transcriptionDuration!) : "N/A")
                                MetadataRow(label: "AI Enhancement Duration", value: transcription.enhancementDuration != nil ? String(format: "%.2fs", transcription.enhancementDuration!) : "N/A")
                                MetadataRow(label: "Preset Prompt Style", value: transcription.promptName ?? "Default Speech Style")
                                MetadataRow(label: "Power Mode Config", value: transcription.powerModeName != nil ? "\(transcription.powerModeEmoji ?? "⚡") \(transcription.powerModeName!)" : "None")
                                MetadataRow(label: "Unique Dictation ID", value: transcription.id.uuidString)
                            }
                            .padding(14)
                            .background(Color(red: 0.98, green: 0.98, blue: 0.99))
                            .cornerRadius(10)
                        } else {
                            // AI Prompt Context
                            VStack(alignment: .leading, spacing: 12) {
                                if let sysMsg = transcription.aiRequestSystemMessage, !sysMsg.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("System Instruction Prompt")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.secondary)
                                        ScrollView {
                                            Text(sysMsg)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18).opacity(0.8))
                                                .padding(10)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color.white)
                                                .cornerRadius(6)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                                                )
                                        }
                                        .frame(maxHeight: 120)
                                    }
                                } else {
                                    Text("No custom system instructions prompt context was active.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                
                                Divider().opacity(0.3)
                                
                                if let userMsg = transcription.aiRequestUserMessage, !userMsg.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("User Prompt Context")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.secondary)
                                        ScrollView {
                                            Text(userMsg)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18).opacity(0.8))
                                                .padding(10)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color.white)
                                                .cornerRadius(6)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                                                )
                                        }
                                        .frame(maxHeight: 120)
                                    }
                                }
                            }
                            .padding(14)
                            .background(Color(red: 0.98, green: 0.98, blue: 0.99))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Color.white)
    }

    private var statusColor: Color {
        let rawStatus = transcription.transcriptionStatus ?? "completed"
        switch rawStatus {
        case "completed": return .green
        case "pending": return .orange
        case "canceled": return .gray
        case "failed": return .red
        default: return .green
        }
    }

    private var statusText: String {
        let rawStatus = transcription.transcriptionStatus ?? "completed"
        switch rawStatus {
        case "completed": return "✓ Completed"
        case "pending": return "• Processing"
        case "canceled": return "✗ Canceled"
        case "failed": return "✗ Failed"
        default: return "✓ Completed"
        }
    }
}

// MARK: - Metric Tile Card Helper

struct MetricTileCard: View {
    let icon: String
    let title: String
    let value: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accentColor.opacity(0.08))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.01), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Metadata Row Helper

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Border extension for custom tabs

extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX - width
                }
            }

            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY - width
                }
            }

            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return width
                }
            }

            var h: CGFloat {
                switch edge {
                case .top, .bottom: return width
                case .leading, .trailing: return rect.height
                }
            }

            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}
