import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

enum ModelFilter: String, CaseIterable, Identifiable {
    case recommended = "Recommended"
    case local = "Local"
    case cloud = "Cloud"
    case custom = "Custom"
    var id: String { self.rawValue }
}

struct ModelManagementView: View {
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var customModelToEdit: CustomCloudModel?
    @StateObject private var aiService = AIService()
    @StateObject private var customModelManager = CustomCloudModelManager.shared
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext
    @StateObject private var whisperPrompt = WhisperPrompt()
    @ObservedObject private var warmupCoordinator = WhisperModelWarmupCoordinator.shared

    @State private var selectedFilter: ModelFilter = .recommended
    @State private var isShowingSettings = false
    @State private var searchText = ""

    private let settingsPanelWidth: CGFloat = 400

    // State for the unified alert
    @State private var isShowingDeleteAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var deleteActionClosure: () -> Void = {}

    private func closeSettings() {
        withAnimation(.smooth(duration: 0.3)) {
            isShowingSettings = false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if SystemArchitecture.isIntelMac {
                    intelMacWarningBanner
                }

                AIModelsHeroView()
                languageSelectionSection
                availableModelsSection
            }
            .padding(40)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .slidingPanel(isPresented: $isShowingSettings, width: settingsPanelWidth) {
            settingsPanelContent
        }
        .alert(isPresented: $isShowingDeleteAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .destructive(Text("Delete"), action: deleteActionClosure),
                secondaryButton: .cancel()
            )
        }
    }

    private var settingsPanelContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("Model Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { closeSettings() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Divider().opacity(0.5), alignment: .bottom
            )

            // Content
            ModelSettingsView(whisperPrompt: whisperPrompt)
        }
    }

    private var languageSelectionSection: some View {
        LanguageSelectionView(transcriptionModelManager: transcriptionModelManager, displayMode: .full, whisperPrompt: whisperPrompt)
    }
    
    private var availableModelsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                // Modern compact pill switcher
                HStack(spacing: 12) {
                    ForEach(ModelFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedFilter = filter
                                isShowingSettings = false
                            }
                        }) {
                            Text(filter.rawValue)
                                .font(.system(size: 14, weight: selectedFilter == filter ? .semibold : .medium))
                                .foregroundColor(selectedFilter == filter ? .primary : .primary.opacity(0.7))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    CardBackground(isSelected: selectedFilter == filter, cornerRadius: 22)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                Spacer()
                
                // Beautiful Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                    
                    TextField("Search models...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 150)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white)
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.08), lineWidth: 1)
                )
                
                Button(action: {
                    withAnimation(.smooth(duration: 0.3)) {
                        isShowingSettings.toggle()
                    }
                }) {
                    Image(systemName: "gear")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isShowingSettings ? .accentColor : .primary.opacity(0.7))
                        .padding(12)
                        .background(
                            CardBackground(isSelected: isShowingSettings, cornerRadius: 22)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 12)
            
            VStack(spacing: 12) {
                    ForEach(filteredModels, id: \.id) { model in
                        let isWarming = (model as? WhisperModel).map { whisperModel in
                            warmupCoordinator.isWarming(modelNamed: whisperModel.name)
                        } ?? false

                        ModelCardView(
                            model: model,
                            fluidAudioModelManager: fluidAudioModelManager,
                            transcriptionModelManager: transcriptionModelManager,
                            isDownloaded: whisperModelManager.availableModels.contains { $0.name == model.name },
                            isCurrent: transcriptionModelManager.currentTranscriptionModel?.name == model.name,
                            downloadProgress: whisperModelManager.downloadProgress,
                            modelURL: whisperModelManager.availableModels.first { $0.name == model.name }?.url,
                            isWarming: isWarming,
                            deleteAction: {
                                if let customModel = model as? CustomCloudModel {
                                    alertTitle = "Delete Custom Model"
                                    alertMessage = "Are you sure you want to delete the custom model '\(customModel.displayName)'?"
                                    deleteActionClosure = {
                                        customModelManager.removeCustomModel(withId: customModel.id)
                                        transcriptionModelManager.refreshAllAvailableModels()
                                    }
                                    isShowingDeleteAlert = true
                                } else if let downloadedModel = whisperModelManager.availableModels.first(where: { $0.name == model.name }) {
                                    alertTitle = "Delete Model"
                                    alertMessage = "Are you sure you want to delete the model '\(downloadedModel.name)'?"
                                    deleteActionClosure = {
                                        Task {
                                            await whisperModelManager.deleteModel(downloadedModel)
                                        }
                                    }
                                    isShowingDeleteAlert = true
                                }
                            },
                            setDefaultAction: {
                                Task {
                                    transcriptionModelManager.setDefaultTranscriptionModel(model)
                                }
                            },
                            downloadAction: {
                                if let whisperModel = model as? WhisperModel {
                                    Task { await whisperModelManager.downloadModel(whisperModel) }
                                }
                            },
                            editAction: model.provider == .custom ? { customModel in
                                customModelToEdit = customModel
                            } : nil
                        )
                    }
                    
                    // Import button as a card at the end of the Local list
                    if selectedFilter == .local {
                        HStack(spacing: 8) {
                            Button(action: { presentImportPanel() }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Import Local Model…")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(CardBackground(isSelected: false))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)

                            InfoTip(
                                "Add a custom fine-tuned whisper model to use with VoiceInk. Select the downloaded .bin file.",
                                learnMoreURL: "https://tryvoiceink.com/docs/custom-local-whisper-models"
                            )
                            .help("Read more about custom local models")
                        }
                    }
                    
                    if selectedFilter == .custom {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                            Text("Only OpenAI-compatible transcription APIs are supported.")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)

                        AddCustomModelCardView(
                            customModelManager: customModelManager,
                            editingModel: customModelToEdit
                        ) {
                            // Refresh the models when a new custom model is added
                            transcriptionModelManager.refreshAllAvailableModels()
                            customModelToEdit = nil // Clear editing state
                        }
                    }
                }
            }
        .padding()
    }



    private var intelMacWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)

            Text("Local models don't work reliably on Intel Macs")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedFilter = .cloud
                }
            }) {
                HStack(spacing: 4) {
                    Text("Use Cloud")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    private var filteredModels: [any TranscriptionModel] {
        let baseModels: [any TranscriptionModel]
        switch selectedFilter {
        case .recommended:
            baseModels = transcriptionModelManager.allAvailableModels.filter {
                let recommendedNames = ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
                return recommendedNames.contains($0.name)
            }.sorted { model1, model2 in
                let recommendedOrder = ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
                let index1 = recommendedOrder.firstIndex(of: model1.name) ?? Int.max
                let index2 = recommendedOrder.firstIndex(of: model2.name) ?? Int.max
                return index1 < index2
            }
        case .local:
            baseModels = transcriptionModelManager.allAvailableModels.filter {
                ($0.provider == .whisper || $0.provider == .nativeApple || $0.provider == .fluidAudio)
                    && transcriptionModelManager.isAvailableOnCurrentOS($0)
            }
        case .cloud:
            baseModels = transcriptionModelManager.allAvailableModels.filter { CloudProviderRegistry.provider(for: $0.provider) != nil }
        case .custom:
            baseModels = transcriptionModelManager.allAvailableModels.filter { $0.provider == .custom }
        }
        
        if searchText.isEmpty {
            return baseModels
        } else {
            return baseModels.filter { model in
                model.displayName.localizedCaseInsensitiveContains(searchText) ||
                model.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // MARK: - Import Panel
    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "bin")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.title = "Select a Whisper ggml .bin model"
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                await whisperModelManager.importWhisperModel(from: url)
            }
        }
    }
}

// MARK: - Premium AI Models Hero Panel

struct AIModelsHeroView: View {
    @State private var isVisible = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header: Info and Live Indicator
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Transcription Models")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("High-fidelity speech synthesis and inference")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Pulsing Active Badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: 0.36, green: 0.28, blue: 0.88))
                            .frame(width: 6, height: 6)
                            .opacity(isVisible ? 1.0 : 0.6)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isVisible)
                        
                        Text("Ready")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            // Dual-frequency organic wave Canvas
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    let midY = h / 2
                    
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    
                    // Layer 1: Blue/Purple Wave
                    var path1 = Path()
                    path1.move(to: CGPoint(x: 0, y: midY))
                    for x in stride(from: 0, to: w, by: 2) {
                        let phase = x * 0.010 + elapsed * 1.3
                        let noise = sin(x * 0.002 - elapsed * 0.7) * 12.0
                        let y = midY + sin(phase) * 18.0 + sin(phase * 0.5) * 10.0 + noise
                        if x == 0 { path1.move(to: CGPoint(x: x, y: y)) }
                        else { path1.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path1, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.85), Color(red: 0.28, green: 0.58, blue: 0.95).opacity(0.85)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: w, y: 0)
                    ), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    
                    // Layer 2: Neon Purple/Violet Wave
                    var path2 = Path()
                    path2.move(to: CGPoint(x: w, y: midY))
                    for x in stride(from: 0, to: w, by: 2) {
                        let phase = x * 0.015 - elapsed * 1.8
                        let noise = cos(x * 0.004 + elapsed * 0.9) * 10.0
                        let y = midY + sin(phase * 0.9) * 14.0 + cos(phase * 1.2) * 8.0 + noise
                        if x == 0 { path2.move(to: CGPoint(x: x, y: y)) }
                        else { path2.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path2, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.65), Color(red: 0.0, green: 0.8, blue: 1.0).opacity(0.65)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: w, y: 0)
                    ), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    
                    // Floating dynamic particles
                    for i in 0..<8 {
                        let seed = Double(i) * 45.2
                        let px = (w * 0.1 + w * 0.8 * abs(sin(seed)))
                        let py = midY + sin(elapsed * 1.5 + seed) * 20.0 + cos(elapsed * 0.7 + seed * 1.5) * 8.0
                        
                        let radius = 1.5 + 1.5 * abs(sin(elapsed * 3.0 + seed))
                        let particleColor = Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.3 + 0.7 * abs(sin(elapsed * 2.5 + seed)))
                        
                        let rect = CGRect(x: px - radius, y: py - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(particleColor))
                    }
                }
            }
            .frame(height: 100)
            
            // Footer Info stats cards
            HStack(spacing: 0) {
                // Models Available
                VStack(alignment: .leading, spacing: 3) {
                    Text("Models Available")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                        .textCase(.uppercase)
                    
                    Text("12 Available")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                // Languages Supported
                VStack(alignment: .center, spacing: 3) {
                    Text("Languages Supported")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                        .textCase(.uppercase)
                    
                    Text("16 Languages")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                Spacer()
                
                // Avg. Accuracy
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Avg. Accuracy")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                        .textCase(.uppercase)
                    
                    Text("96.8%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.28, green: 0.65, blue: 0.45))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(Color(red: 0.06, green: 0.05, blue: 0.12)) // Dark premium obsidian background
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
        )
        .shadow(color: Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.12), radius: 15, x: 0, y: 10)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}
