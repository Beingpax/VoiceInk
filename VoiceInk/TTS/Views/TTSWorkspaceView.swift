import SwiftUI
import AppKit

private enum ContextPanelDestination: String, CaseIterable, Identifiable {
    case queue
    case history
    case snippets
    case glossary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queue:
            return "Queue"
        case .history:
            return "History"
        case .snippets:
            return "Library"
        case .glossary:
            return "Glossary"
        }
    }

    var icon: String {
        switch self {
        case .queue:
            return "list.bullet.rectangle"
        case .history:
            return "clock.arrow.circlepath"
        case .snippets:
            return "text.badge.star"
        case .glossary:
            return "character.bubble"
        }
    }
}

private enum InspectorSection: String, CaseIterable, Identifiable {
    case cost
    case transcript
    case notifications
    case provider

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cost:
            return "Cost"
        case .transcript:
            return "Transcript"
        case .notifications:
            return "Alerts"
        case .provider:
            return "Provider"
        }
    }

    var icon: String {
        switch self {
        case .cost:
            return "dollarsign.circle"
        case .transcript:
            return "doc.text"
        case .notifications:
            return "bell"
        case .provider:
            return "info.circle"
        }
    }
}

private enum ComposerUtility: String, CaseIterable, Identifiable {
    case transcription
    case urlImport
    case sampleText
    case chunking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcription:
            return "Transcription"
        case .urlImport:
            return "URL Import"
        case .sampleText:
            return "Sample Text"
        case .chunking:
            return "Chunk Helper"
        }
    }

    var icon: String {
        switch self {
        case .transcription:
            return "waveform"
        case .urlImport:
            return "link.badge.plus"
        case .sampleText:
            return "text.quote"
        case .chunking:
            return "square.split.2x2"
        }
    }

    var helpText: String {
        switch self {
        case .transcription:
            return "Transcribe an audio recording and generate a cleaned script"
        case .urlImport:
            return "Pull readable text from a web article"
        case .sampleText:
            return "Fill the editor with ready-made copy"
        case .chunking:
            return "Preview how your batch segments will split"
        }
    }
}

struct TTSWorkspaceView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var selectedContextPanel: ContextPanelDestination? = .queue
    @State private var isInspectorVisible = false
    @State private var inspectorSection: InspectorSection = .cost
    @State private var activeUtility: ComposerUtility?
    @State private var showingInspectorPopover = false

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 960
            let horizontalPadding = LayoutGuidance.horizontalPadding(for: proxy.size.width,
                                                                     isMinimalist: viewModel.isMinimalistMode)
            let commandVerticalPadding: CGFloat = viewModel.isMinimalistMode ? 10 : 12
            let composerVerticalPadding: CGFloat = viewModel.isMinimalistMode ? 16 : 20

            VStack(spacing: 0) {
                CommandStripView(
                    isCompact: isCompact,
                    isInspectorVisible: isInspectorVisible,
                    showingSettings: $showingSettings,
                    showingAbout: $showingAbout,
                    toggleInspector: {
                        if isCompact {
                            showingInspectorPopover = true
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isInspectorVisible.toggle()
                            }
                        }
                    },
                    focusInspector: { section in
                        inspectorSection = section
                        if isCompact {
                            showingInspectorPopover = true
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isInspectorVisible = true
                            }
                        }
                    }
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, commandVerticalPadding)
                .background(Color(NSColor.windowBackgroundColor))
                .popover(isPresented: $showingInspectorPopover, arrowEdge: .top) {
                    InspectorPanelView(selection: $inspectorSection, onClose: {
                        showingInspectorPopover = false
                    })
                    .frame(minWidth: 280, idealWidth: 320)
                    .environmentObject(viewModel)
                }

                Divider()

                if isCompact {
                    CompactWorkspace(
                        horizontalPadding: horizontalPadding,
                        verticalPadding: composerVerticalPadding,
                        selectedContextPanel: $selectedContextPanel,
                        activeUtility: $activeUtility,
                        focusInspector: { section in
                            inspectorSection = section
                            showingInspectorPopover = true
                        }
                    )
                    .environmentObject(viewModel)
                } else {
                    WideWorkspace(
                        selectedContextPanel: $selectedContextPanel,
                        activeUtility: $activeUtility,
                        inspectorSection: $inspectorSection,
                        isInspectorVisible: $isInspectorVisible,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: composerVerticalPadding,
                        focusInspector: { section in
                            inspectorSection = section
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isInspectorVisible = true
                            }
                        }
                    )
                    .environmentObject(viewModel)
                }

                Divider()

                PlaybackBarView(horizontalPadding: horizontalPadding)
                    .background(Color(NSColor.windowBackgroundColor))
            }
            .background(Color(NSColor.controlBackgroundColor).ignoresSafeArea())
        }
        .frame(minWidth: 800, minHeight: 600)
        .preferredColorScheme(viewModel.colorSchemeOverride)
        .sheet(isPresented: $showingSettings) {
            TTSSettingsView()
                .environmentObject(viewModel)
                .preferredColorScheme(viewModel.colorSchemeOverride)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .overlay(
            HStack(spacing: 0) {
                Button(action: {
                    viewModel.playbackSpeed = max(0.5, viewModel.playbackSpeed - 0.25)
                    viewModel.applyPlaybackSpeed(save: true)
                }) { EmptyView() }
                .keyboardShortcut("[", modifiers: .command)

                Button(action: {
                    viewModel.playbackSpeed = min(2.0, viewModel.playbackSpeed + 0.25)
                    viewModel.applyPlaybackSpeed(save: true)
                }) { EmptyView() }
                .keyboardShortcut("]", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0.01)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        )
        .onAppear {
            viewModel.updateAvailableVoices()
        }
    }
}

// MARK: - Command Strip

private struct CommandStripView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let isCompact: Bool
    let isInspectorVisible: Bool
    @Binding var showingSettings: Bool
    @Binding var showingAbout: Bool
    let toggleInspector: () -> Void
    let focusInspector: (InspectorSection) -> Void
    @State private var showAdvancedPanel = false
    @State private var showingTranslationPopover = false
    @State private var showingStylePopover = false
    @State private var showingPreviewPopover = false

    var body: some View {
        Group {
            if isCompact {
                wrappedLayout
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalLayout
                        .fixedSize(horizontal: true, vertical: false)
                    wrappedLayout
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .popover(isPresented: $showAdvancedPanel, arrowEdge: .top) {
            AdvancedControlsPanelView()
                .environmentObject(viewModel)
                .frame(width: 300)
        }
    }

    private var horizontalLayout: some View {
        HStack(spacing: 12) {
            providerAndVoice
            Divider()
                .frame(height: 24)
            characterCount
            Spacer(minLength: 12)
            statusIndicator
            voicePreviewButton
            voiceStyleButton
            translationControl
            batchButton
            generateButton
            exportButton
            transcriptMenu
            clearButton
            advancedButton
            overflowMenu
        }
    }

    private var wrappedLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                providerAndVoice
                Spacer()
                statusIndicator
            }

            HStack(spacing: 12) {
                characterCount
                Spacer()
                voicePreviewButton
                voiceStyleButton
                translationControl
                batchButton
                generateButton
                exportButton
                transcriptMenu
                clearButton
                advancedButton
                overflowMenu
            }
        }
    }

    private var providerAndVoice: some View {
        HStack(spacing: 12) {
            Picker("Provider", selection: $viewModel.selectedProvider) {
                ForEach(TTSProviderType.allCases, id: \.self) { provider in
                    Label(provider.displayName, systemImage: provider.icon)
                        .tag(provider)
                }
            }
            .onChange(of: viewModel.selectedProvider) {
                viewModel.updateAvailableVoices()
            }
            .frame(minWidth: 160)
            .pickerStyle(MenuPickerStyle())
            .help("Choose the speech provider")

            Picker("Voice", selection: $viewModel.selectedVoice) {
                Text("Default").tag(nil as Voice?)
                ForEach(viewModel.availableVoices) { voice in
                    Text(voice.name).tag(voice as Voice?)
                }
            }
            .frame(minWidth: 160)
            .pickerStyle(MenuPickerStyle())
            .help("Select the voice for this provider")
        }
    }

    private var voicePreviewButton: some View {
        Button {
            showingPreviewPopover = true
        } label: {
            Label(voicePreviewButtonText, systemImage: voicePreviewButtonIcon)
                .commandLabelFixedSize()
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.availableVoices.isEmpty)
        .popover(isPresented: $showingPreviewPopover, arrowEdge: .top) {
            VoicePreviewPopover(isPresented: $showingPreviewPopover)
                .environmentObject(viewModel)
        }
        .help("Listen to sample audio for available voices")
    }

    private var voicePreviewButtonText: String {
        if viewModel.isPreviewPlaying, let name = viewModel.previewVoiceName {
            return "Previewing \(name)"
        } else if let name = viewModel.previewVoiceName {
            return "Preview: \(name)"
        } else {
            return "Preview Voice"
        }
    }

    private var voicePreviewButtonIcon: String {
        if viewModel.isPreviewLoadingActive {
            return "hourglass"
        } else if viewModel.isPreviewPlaying {
            return "speaker.wave.2.fill"
        } else {
            return "play.circle"
        }
    }

    private var voiceStyleButton: some View {
        Button {
            showingStylePopover = true
        } label: {
            Label("Voice Style", systemImage: "slider.horizontal.2.rectangle")
                .commandLabelFixedSize()
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.hasActiveStyleControls)
        .popover(isPresented: $showingStylePopover, arrowEdge: .top) {
            VoiceStylePopover(isPresented: $showingStylePopover)
                .environmentObject(viewModel)
        }
        .help("Adjust emotion and tone controls for the selected provider")
    }

    private var characterCount: some View {
        let count = viewModel.effectiveCharacterCount
        let formattedLimit = viewModel.formattedCharacterLimit(for: viewModel.selectedProvider)
        let formattedCount = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
        return Label("Characters: \(formattedCount)/\(formattedLimit)", systemImage: "textformat.alt")
            .font(.footnote)
            .foregroundColor(viewModel.shouldHighlightCharacterOverflow ? .red : .secondary)
            .accessibilityLabel("Character count")
            .commandLabelFixedSize()
    }

    private var translationControl: some View {
        Button {
            showingTranslationPopover = true
        } label: {
            if viewModel.isTranslating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Translating…")
                }
                .commandLabelFixedSize()
            } else {
                Label("Translate", systemImage: "arrow.triangle.2.circlepath")
                    .commandLabelFixedSize()
            }
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $showingTranslationPopover, arrowEdge: .top) {
            TranslationSettingsPopover(isPresented: $showingTranslationPopover)
                .environmentObject(viewModel)
        }
        .help("Configure translation options and translate the current text")
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if viewModel.isGenerating {
            HStack(spacing: 6) {
                ProgressView(value: viewModel.generationProgress)
                    .frame(width: 80)
                Text("Generating")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .commandLabelFixedSize()
        } else if viewModel.isPlaying {
            Label("Playing", systemImage: "speaker.wave.2.fill")
                .font(.footnote)
                .foregroundColor(.green)
                .commandLabelFixedSize()
        }
    }

    private var batchButton: some View {
        Button(action: viewModel.startBatchGeneration) {
            Label("Batch", systemImage: "text.badge.plus")
                .commandLabelFixedSize()
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.hasBatchableSegments || viewModel.isGenerating || viewModel.isBatchRunning)
        .help("Generate every segment separated by ---")
    }

    private var generateButton: some View {
        Button {
            Task { await viewModel.generateSpeech() }
        } label: {
            Label("Generate", systemImage: "waveform")
                .fontWeight(.semibold)
                .commandLabelFixedSize()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isGenerating)
        .help("Generate speech from the editor text (⌘↵)")
    }

    private var exportButton: some View {
        Button(action: viewModel.exportAudio) {
            Label("Export", systemImage: "square.and.arrow.down")
                .commandLabelFixedSize()
        }
        .buttonStyle(.bordered)
        .keyboardShortcut("e", modifiers: .command)
        .disabled(viewModel.audioData == nil)
        .help("Export the most recent audio file (⌘E)")
    }

    private var transcriptMenu: some View {
        Menu {
            Button("Export SRT") {
                viewModel.exportTranscript(format: .srt)
            }
            Button("Export VTT") {
                viewModel.exportTranscript(format: .vtt)
            }
        } label: {
            Label("Transcript", systemImage: "doc.text")
                .commandLabelFixedSize()
        }
        .disabled(viewModel.currentTranscript == nil)
        .help("Export the transcript for the current audio")
    }

    private var clearButton: some View {
        Button(action: viewModel.clearText) {
            Label("Clear", systemImage: "trash")
                .commandLabelFixedSize()
        }
        .buttonStyle(.bordered)
        .keyboardShortcut("k", modifiers: .command)
        .help("Clear the editor and audio (⌘K)")
    }

    private var advancedButton: some View {
        Button {
            showAdvancedPanel = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .imageScale(.large)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Show advanced playback and export controls")
    }

    private var overflowMenu: some View {
        Menu {
            Button(isInspectorVisible ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right") {
                toggleInspector()
            }

            Button("View Cost Detail", systemImage: "dollarsign.circle") {
                focusInspector(.cost)
            }

            Menu("Appearance", systemImage: "paintbrush") {
                Picker("Appearance", selection: $viewModel.appearancePreference) {
                    ForEach(AppearancePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.inline)
            }

            Button(viewModel.isMinimalistMode ? "Disable Compact Layout" : "Enable Compact Layout", systemImage: "rectangle.compress.vertical") {
                viewModel.isMinimalistMode.toggle()
                viewModel.saveSettings()
            }

            Divider()

            Button("Settings", systemImage: "gear") {
                showingSettings = true
            }

            Button("About", systemImage: "info.circle") {
                showingAbout = true
            }

            Button("Donate", systemImage: "heart.fill") {
                if let url = AppConfiguration.donationURL {
                    NSWorkspace.shared.open(url)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.large)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .help("More options")
    }
}

private struct CompactWorkspace: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    @Binding var selectedContextPanel: ContextPanelDestination?
    @Binding var activeUtility: ComposerUtility?
    let focusInspector: (InspectorSection) -> Void

    var body: some View {
        MainComposerColumn(
            isCompact: true,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            selectedContextPanel: $selectedContextPanel,
            activeUtility: $activeUtility,
            focusInspector: focusInspector
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .layoutPriority(1)
    }
}

private struct WideWorkspace: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var selectedContextPanel: ContextPanelDestination?
    @Binding var activeUtility: ComposerUtility?
    @Binding var inspectorSection: InspectorSection
    @Binding var isInspectorVisible: Bool
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let focusInspector: (InspectorSection) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ContextRailView(selection: $selectedContextPanel)
                .frame(width: 68)
                .background(Color(NSColor.windowBackgroundColor))

            if let selection = selectedContextPanel {
                Divider()
                ContextPanelContainer(selection: selection) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedContextPanel = nil
                    }
                }
                .frame(minWidth: 260, idealWidth: 300, maxHeight: .infinity)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Divider()

            MainComposerColumn(
                isCompact: false,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                selectedContextPanel: $selectedContextPanel,
                activeUtility: $activeUtility,
                focusInspector: focusInspector
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .layoutPriority(1)

            if isInspectorVisible {
                Divider()
                SmartInspectorColumn(selection: $inspectorSection,
                                     collapse: {
                                         withAnimation(.easeInOut(duration: 0.2)) {
                                             isInspectorVisible = false
                                         }
                                     })
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct SmartInspectorColumn: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var selection: InspectorSection
    let collapse: () -> Void

    var body: some View {
        InspectorPanelView(selection: $selection, onClose: collapse)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private extension View {
    func commandLabelFixedSize() -> some View {
        fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Main Composer

private struct MainComposerColumn: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let isCompact: Bool
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    @Binding var selectedContextPanel: ContextPanelDestination?
    @Binding var activeUtility: ComposerUtility?
    let focusInspector: (InspectorSection) -> Void
    @State private var showingTranslationDetail = false

    var body: some View {
        ViewThatFits(in: .vertical) {
            composerStack()

            ScrollView {
                composerStack()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingTranslationDetail) {
            if let translation = viewModel.translationResult {
                TranslationComparisonView(translation: translation)
                    .environmentObject(viewModel)
                    .frame(minWidth: 600, minHeight: 420)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func composerStack() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if isCompact {
                ContextSwitcher(selectedContext: $selectedContextPanel)

                if let selection = selectedContextPanel {
                    ContextPanelCard(selection: selection)
                }
            }

            ComposerUtilityBar(activeUtility: $activeUtility)

            if let utility = activeUtility {
                UtilityDetailView(utility: utility, dismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeUtility = nil
                    }
                })
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            TextEditorView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ContextShelfView(showingTranslationDetail: $showingTranslationDetail,
                             focusInspector: focusInspector)

            GenerationStatusFooter(focusInspector: focusInspector)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ContextShelfView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var showingTranslationDetail: Bool
    let focusInspector: (InspectorSection) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if viewModel.articleSummary != nil || viewModel.isSummarizingArticle || viewModel.articleSummaryError != nil {
                ArticleSummaryCard()
            }

            if let translation = viewModel.translationResult, viewModel.translationKeepOriginal {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Translation", systemImage: "globe")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(translation.targetLanguageDisplayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(translation.translatedText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(3)

                    HStack {
                        Button("Use Translation") {
                            viewModel.adoptTranslationAsInput()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("View Details") {
                            showingTranslationDetail = true
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Cost Estimate", systemImage: "dollarsign.circle")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(viewModel.costEstimateSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let detail = viewModel.costEstimateDetail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                } else {
                    Text("Estimate reflects your current provider and text length.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }

                HStack {
                    Spacer()
                    Button("Open Inspector") {
                        focusInspector(.cost)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: viewModel.translationResult)
    }
}

private struct ArticleSummaryCard: View {
    @EnvironmentObject var viewModel: TTSViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Smart Import", systemImage: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let host = viewModel.articleSummary?.sourceURL.host {
                    Text(host)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.isSummarizingArticle {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Cleaning the article with AI…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let summary = viewModel.articleSummaryPreview {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(4)
            } else if let error = viewModel.articleSummaryError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                Text("Use Import to pull a web article and see an AI summary here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let reduction = viewModel.articleSummaryReductionDescription {
                Text(reduction)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("Use Concise Article") {
                    viewModel.replaceEditorWithCondensedImport()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canAdoptCondensedImport)

                Button("Insert Summary") {
                    viewModel.insertSummaryIntoEditor()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canInsertSummaryIntoEditor)

                Spacer()

                Button("Speak Summary") {
                    Task {
                        await viewModel.speakSummaryOfImportedArticle()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSpeakSummary || viewModel.isGenerating)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSummarizingArticle)
        .animation(.easeInOut(duration: 0.2), value: viewModel.articleSummary)
    }
}

private struct ContextSwitcher: View {
    @Binding var selectedContext: ContextPanelDestination?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ContextPanelDestination.allCases) { destination in
                    let isSelected = selectedContext == destination
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedContext = isSelected ? nil : destination
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: destination.icon)
                            Text(destination.title)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help(destination.title)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ContextPanelCard: View {
    let selection: ContextPanelDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(selection.title, systemImage: selection.icon)
                .font(.headline)

            Divider()

            ContextPanelContent(selection: selection)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

private struct ComposerUtilityBar: View {
    @Binding var activeUtility: ComposerUtility?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ComposerUtility.allCases) { utility in
                let isActive = activeUtility == utility
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeUtility = isActive ? nil : utility
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: utility.icon)
                        Text(utility.title)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help(utility.helpText)
            }

            Spacer()
        }
    }
}

private struct TranslationComparisonView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let translation: TranslationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label("Translation Preview", systemImage: "globe")
                    .font(.headline)

                Spacer()

                if let detected = viewModel.translationDetectedLanguageDisplayName {
                    Text("Detected: \(detected)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("→ \(translation.targetLanguageDisplayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Use Translation") {
                    viewModel.adoptTranslationAsInput()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Replace the editor text with the translated version")
            }

            Divider()

            HStack(alignment: .top, spacing: 12) {
                translationColumn(
                    title: "Original",
                    languageLabel: viewModel.translationDetectedLanguageDisplayName ?? "",
                    text: translation.originalText
                )

                translationColumn(
                    title: "Translated",
                    languageLabel: translation.targetLanguageDisplayName,
                    text: translation.translatedText
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private func translationColumn(title: String, languageLabel: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if !languageLabel.isEmpty {
                        Text(languageLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Copy this text to the clipboard")
            }

            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.windowBackgroundColor))
                    )
            }
            .frame(minHeight: 140, maxHeight: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TranslationSettingsPopover: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Translation")
                    .font(.headline)
                Text("Choose a target language and optionally keep the original text alongside the translated copy.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Picker("Target language", selection: $viewModel.translationTargetLanguage) {
                ForEach(viewModel.availableTranslationLanguages) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)

            Toggle("Keep original text", isOn: $viewModel.translationKeepOriginal)

            if !viewModel.canTranslate {
                Label("Add an OpenAI API key in Settings to enable translation.", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }

            Divider()

            HStack {
                Spacer()

                if viewModel.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }

                Button {
                    Task {
                        await viewModel.translateCurrentText()
                        isPresented = false
                    }
                } label: {
                    Label("Translate Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isTranslating || !viewModel.canTranslate || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 260)
    }
}

private struct VoicePreviewPopover: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Preview")
                    .font(.headline)
                Text("Play a short sample for any available voice. Fallback previews synthesize a brief line when no hosted clip is provided.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if viewModel.availableVoices.isEmpty {
                Text("No voices are available for the selected provider.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.availableVoices) { voice in
                            Button {
                                viewModel.previewVoice(voice)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .center, spacing: 8) {
                                        Text(voice.name)
                                            .fontWeight(viewModel.isPreviewingVoice(voice) ? .semibold : .regular)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        previewStatusIcon(for: voice)
                                    }

                                    Text(voice.language)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    if !viewModel.canPreview(voice) {
                                        Text("Add an API key in Settings to preview this voice.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(rowBackground(for: voice))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(rowBorderColor(for: voice), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!viewModel.canPreview(voice))
                            .opacity(viewModel.canPreview(voice) ? 1 : 0.55)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .frame(maxHeight: 260)
            }

            if viewModel.isPreviewActive {
                Divider()
                Button {
                    viewModel.stopPreview()
                } label: {
                    Label("Stop Preview", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 280)
    }

    private func rowBackground(for voice: Voice) -> some ShapeStyle {
        if viewModel.isPreviewingVoice(voice) || viewModel.isPreviewLoadingVoice(voice) {
            return Color.accentColor.opacity(0.15)
        }
        return Color.clear
    }

    private func rowBorderColor(for voice: Voice) -> Color {
        if viewModel.isPreviewingVoice(voice) || viewModel.isPreviewLoadingVoice(voice) {
            return Color.accentColor.opacity(0.4)
        }
        return Color.secondary.opacity(0.3)
    }

    @ViewBuilder
    private func previewStatusIcon(for voice: Voice) -> some View {
        if viewModel.isPreviewLoadingVoice(voice) {
            ProgressView()
                .controlSize(.small)
        } else if viewModel.isPreviewingVoice(voice) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundColor(.accentColor)
        } else if viewModel.canPreview(voice) {
            Image(systemName: "play.circle")
                .foregroundColor(.secondary)
        } else {
            Image(systemName: "key.slash")
                .foregroundColor(.secondary)
        }
    }
}

private struct VoiceStylePopover: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Style")
                    .font(.headline)
                Text("Fine-tune expressive controls for the current provider. Settings persist per provider and reset automatically when unsupported.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if viewModel.hasActiveStyleControls {
                HStack {
                    Text("Presets")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        viewModel.resetStyleControls()
                    } label: {
                        Label("Reset All", systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canResetStyleControls)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.activeStyleControls) { control in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(control.label)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(control.formattedValue(for: viewModel.currentStyleValue(for: control)))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button {
                                    viewModel.resetStyleControl(control)
                                } label: {
                                    Label("Reset", systemImage: "arrow.uturn.backward")
                                        .labelStyle(.titleAndIcon)
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                .disabled(!viewModel.canResetStyleControl(control))
                            }

                            if let step = control.step {
                                Slider(value: viewModel.binding(for: control), in: control.range, step: step)
                            } else {
                                Slider(value: viewModel.binding(for: control), in: control.range)
                            }

                            if let help = control.helpText {
                                Text(help)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                Label("The selected provider does not expose style controls.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if viewModel.selectedProvider == .elevenLabs {
                Divider()
                ElevenLabsPromptingView()
                    .environmentObject(viewModel)
            }

            Divider()

            HStack {
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 280)
    }
}

private struct UtilityDetailView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let utility: ComposerUtility
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(utility.title, systemImage: utility.icon)
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }

            switch utility {
            case .transcription:
                TranscriptionUtilityView()
                    .environmentObject(viewModel)
            case .urlImport:
                URLImportView()
                    .environmentObject(viewModel)
            case .sampleText:
                SampleTextUtilityView(onClose: dismiss)
            case .chunking:
                ChunkingHelperView()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

private struct SampleTextUtilityView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Replace the editor contents with a ready-made sample to test providers quickly.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Button("Short intro paragraph") {
                    viewModel.inputText = "Hello! This is a sample text to demonstrate the text-to-speech functionality. The app supports multiple providers and voices so you can create natural-sounding speech from any text."
                    onClose()
                }
                Button("Demo feature tour") {
                    viewModel.inputText = """
Welcome to the VoiceInk Text-to-Speech workspace! This experience transforms written text into natural-sounding speech using a curated set of AI voices.

Choose between OpenAI, ElevenLabs, Google Cloud, or the offline Tight Ass Mode. Dial in voice style, playback speed, and export format so each narration fits the moment.

Use the playback bar to review every generation, then export exactly what you need for your project or workflow.
"""
                    onClose()
                }
                Button("Long narrative excerpt") {
                    viewModel.inputText = """
The art of text-to-speech synthesis has evolved dramatically over the past decade. What once sounded robotic now feels natural, expressive, and tailored.

Modern providers use deep learning models trained on vast speech corpora. These networks capture intonation, rhythm, pacing, and emotion to produce rich voices on demand.

From accessibility tools to audiobooks, synthetic narration is reshaping how we consume information. VoiceInk brings those capabilities to the desktop so you can experiment, prototype, and deliver high-quality speech quickly.
"""
                    onClose()
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ChunkingHelperView: View {
    @EnvironmentObject var viewModel: TTSViewModel

    var segments: [String] {
        viewModel.batchSegments(from: viewModel.inputText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use a line containing only --- to mark breaks between segments. Each segment becomes its own generation in the batch queue.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .foregroundColor(.accentColor)
                Text("Detected segments: \(segments.count)")
                    .font(.subheadline)
            }

            if segments.count <= 1 {
                Text("Add --- on its own line to split the script into multiple parts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Segment \(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(segment.count) chars")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(segment)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.windowBackgroundColor))
                        )
                    }
                }
            }
        }
    }
}

private struct GenerationStatusFooter: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let focusInspector: (InspectorSection) -> Void

    var body: some View {
        let formattedLimit = viewModel.formattedCharacterLimit(for: viewModel.selectedProvider)
        let characterCount = viewModel.effectiveCharacterCount
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Characters: \(characterCount)/\(formattedLimit)", systemImage: "textformat.alt")
                    .font(.caption)
                    .foregroundColor(viewModel.shouldHighlightCharacterOverflow ? .red : .secondary)

                Spacer()

                if viewModel.isGenerating {
                    HStack(spacing: 6) {
                        ProgressView(value: viewModel.generationProgress)
                            .frame(width: 100)
                        Text("Generating…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Button {
                focusInspector(.cost)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle")
                        .foregroundColor(.accentColor)
                    Text(viewModel.costEstimate.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View detailed cost estimate")
        }
    }
}

// MARK: - Context Panels

private struct ContextRailView: View {
    @Binding var selection: ContextPanelDestination?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(ContextPanelDestination.allCases) { destination in
                let isSelected = selection == destination
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = isSelected ? nil : destination
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: destination.icon)
                            .imageScale(.large)
                        Text(destination.title)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .help(destination.title)
            }

            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
    }
}

private struct ContextPanelContainer: View {
    let selection: ContextPanelDestination
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(selection.title, systemImage: selection.icon)
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.medium)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            ScrollView {
                ContextPanelContent(selection: selection)
                    .padding(.bottom, 12)
            }
        }
        .padding(20)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct ContextPanelContent: View {
    @EnvironmentObject var viewModel: TTSViewModel
    let selection: ContextPanelDestination

    var body: some View {
        switch selection {
        case .queue:
            BatchQueueView()
                .environmentObject(viewModel)
        case .history:
            RecentGenerationsView()
                .environmentObject(viewModel)
        case .snippets:
            TextSnippetsView()
                .environmentObject(viewModel)
        case .glossary:
            PronunciationGlossaryView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Inspector Panel

private struct InspectorPanelView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var selection: InspectorSection
    let onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Inspector", systemImage: "sidebar.right")
                    .font(.headline)
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.medium)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("Inspector Section", selection: $selection) {
                ForEach(InspectorSection.allCases) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selection {
                    case .cost:
                        CostInspectorContent()
                    case .transcript:
                        TranscriptInspectorContent()
                    case .notifications:
                        NotificationsInspectorContent()
                    case .provider:
                        ProviderInspectorContent()
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .padding(20)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct CostInspectorContent: View {
    @EnvironmentObject var viewModel: TTSViewModel

    var body: some View {
        let estimate = viewModel.costEstimate

        VStack(alignment: .leading, spacing: 12) {
            Label("Estimated cost", systemImage: "dollarsign.circle")
                .font(.headline)

            Text(estimate.summary)
                .font(.body)

            if let detail = estimate.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Refresh estimate") {
                viewModel.objectWillChange.send()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.inputText.isEmpty)
        }
    }
}

private struct TranscriptInspectorContent: View {
    @EnvironmentObject var viewModel: TTSViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Transcript export", systemImage: "doc.text")
                .font(.headline)

            if viewModel.currentTranscript == nil {
                Text("Generate speech to create a transcript you can export as SRT or VTT.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Choose a caption format for the active generation.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Export SRT") {
                        viewModel.exportTranscript(format: .srt)
                    }
                    Button("Export VTT") {
                        viewModel.exportTranscript(format: .vtt)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct NotificationsInspectorContent: View {
    @EnvironmentObject var viewModel: TTSViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Batch alerts", systemImage: "bell")
                .font(.headline)

            Toggle(isOn: Binding(
                get: { viewModel.notificationsEnabled },
                set: { viewModel.setNotificationsEnabled($0) }
            )) {
                Text("Notify me when batch generation completes")
            }

            Text("Notifications use the macOS alert center. You will only be notified for batches with at least one generated segment.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct ProviderInspectorContent: View {
    @EnvironmentObject var viewModel: TTSViewModel

    var body: some View {
        let provider = viewModel.selectedProvider
        let profile = ProviderCostProfile.profile(for: provider)
        let supportedFormats = viewModel.supportedFormats.map(\.displayName).joined(separator: ", ")

        VStack(alignment: .leading, spacing: 12) {
            Label(provider.displayName, systemImage: provider.icon)
                .font(.headline)

            Text(profile.detail)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Supported export formats: \(supportedFormats)")
                .font(.caption)
                .foregroundColor(.secondary)

            if viewModel.selectedVoice == nil {
                Text("Using the provider default voice. Choose a voice from the Command strip to override.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Playback Bar

private struct PlaybackBarView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @State private var isScrubbing = false
    @State private var temporaryTime: TimeInterval = 0
    @State private var showSegmentMarkers = false
    let horizontalPadding: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                transportControls

                Divider()
                    .frame(height: 24)

                timeline

                Divider()
                    .frame(height: 24)

                loopToggle
                speedPicker
                volumeSlider

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSegmentMarkers.toggle()
                    }
                } label: {
                    Image(systemName: showSegmentMarkers ? "chevron.down.circle" : "chevron.up.circle")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .help("Toggle segment markers")
            }

            if showSegmentMarkers {
                SegmentMarkersView(items: viewModel.batchItems)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 12)
    }

    private var transportControls: some View {
        HStack(spacing: 12) {
            Button(action: {
                viewModel.skipBackward()
            }) {
                Image(systemName: "gobackward.10")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.audioData == nil)
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .help("Skip backward 10 seconds (⌘←)")

            Button(action: {
                viewModel.togglePlayPause()
            }) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.audioData == nil)
            .keyboardShortcut(.space, modifiers: [])
            .help("Play or pause (Space)")

            Button(action: {
                viewModel.skipForward()
            }) {
                Image(systemName: "goforward.10")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.audioData == nil)
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .help("Skip forward 10 seconds (⌘→)")

            Button(action: viewModel.stop) {
                Image(systemName: "stop.circle")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.audioData == nil || !viewModel.isPlaying)
            .keyboardShortcut(".", modifiers: .command)
            .help("Stop playback (⌘.)")
        }
    }

    private var timeline: some View {
        HStack(spacing: 10) {
            Text(formatTime(isScrubbing ? temporaryTime : viewModel.currentTime))
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 60, alignment: .trailing)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(
                            width: viewModel.duration > 0 ? geometry.size.width * CGFloat(progressValue) : 0,
                            height: 6
                        )

                    if viewModel.duration > 0 {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 14, height: 14)
                            .offset(x: geometry.size.width * CGFloat(progressValue) - 7)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        isScrubbing = true
                                        let ratio = min(max(value.location.x / geometry.size.width, 0), 1)
                                        temporaryTime = TimeInterval(ratio) * viewModel.duration
                                    }
                                    .onEnded { value in
                                        let ratio = min(max(value.location.x / geometry.size.width, 0), 1)
                                        let newTime = TimeInterval(ratio) * viewModel.duration
                                        viewModel.seek(to: newTime)
                                        isScrubbing = false
                                    }
                            )
                    }
                }
            }
            .frame(height: 18)

            Text(formatTime(viewModel.duration))
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 60, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var loopToggle: some View {
        Button {
            viewModel.isLoopEnabled.toggle()
            viewModel.saveSettings()
        } label: {
            Image(systemName: viewModel.isLoopEnabled ? "repeat.circle.fill" : "repeat")
                .imageScale(.large)
                .foregroundColor(viewModel.isLoopEnabled ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help("Toggle loop playback")
    }

    private var speedPicker: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                Button("\(speed, specifier: "%.2g")×") {
                    viewModel.playbackSpeed = speed
                    viewModel.applyPlaybackSpeed(save: true)
                }
            }
        } label: {
            Label("\(viewModel.playbackSpeed, specifier: "%.2g")×", systemImage: "speedometer")
                .labelStyle(.titleAndIcon)
        }
        .help("Playback speed")
    }

    private var volumeSlider: some View {
        HStack(spacing: 8) {
            Button {
                if viewModel.volume > 0 {
                    viewModel.volume = 0
                } else {
                    viewModel.volume = 0.75
                }
                viewModel.applyPlaybackVolume(save: true)
            } label: {
                Image(systemName: volumeIcon)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .help("Toggle mute")

            Slider(value: Binding(
                get: { viewModel.volume },
                set: { newValue in
                    viewModel.volume = newValue
                    viewModel.applyPlaybackVolume()
                }
            ), in: 0...1) { editing in
                if !editing {
                    viewModel.applyPlaybackVolume(save: true)
                }
            }
            .frame(width: 120)
        }
    }

    private var progressValue: Double {
        if isScrubbing {
            guard viewModel.duration > 0 else { return 0 }
            return temporaryTime / viewModel.duration
        }
        guard viewModel.duration > 0 else { return 0 }
        return viewModel.currentTime / viewModel.duration
    }

    private var volumeIcon: String {
        if viewModel.volume == 0 {
            return "speaker.slash.fill"
        } else if viewModel.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if viewModel.volume < 0.66 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && !time.isInfinite else { return "0:00" }
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

}

private struct SegmentMarkersView: View {
    let items: [BatchGenerationItem]

    var body: some View {
        if items.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundColor(.secondary)
                Text("No queued segments. Add --- between paragraphs to prepare a batch.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(for: item.status))
                                .frame(width: 40, height: 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            Text("\(item.index)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.windowBackgroundColor))
                        )
                        .help(statusText(for: item))
                    }
                }
            }
        }
    }

    private func color(for status: BatchGenerationItem.Status) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .inProgress:
            return .accentColor
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private func statusText(for item: BatchGenerationItem) -> String {
        switch item.status {
        case .pending:
            return "Segment \(item.index) pending"
        case .inProgress:
            return "Segment \(item.index) in progress"
        case .completed:
            return "Segment \(item.index) completed"
        case .failed(let message):
            return "Segment \(item.index) failed: \(message)"
        }
    }
}
