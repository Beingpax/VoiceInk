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
    @ObservedObject var whisperState: WhisperState
    @State private var customModelToEdit: CustomCloudModel?
    @StateObject private var aiService = AIService()
    @StateObject private var customModelManager = CustomModelManager.shared
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext
    @StateObject private var whisperPrompt = WhisperPrompt()
    @ObservedObject private var warmupCoordinator = WhisperModelWarmupCoordinator.shared

    @State private var selectedFilter: ModelFilter = .recommended
    @State private var isShowingSettings = false
    
    // State for the unified alert
    @State private var isShowingDeleteAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var deleteActionClosure: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                defaultModelSection
                languageSelectionSection
                availableModelsSection
            }
            .padding(40)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .alert(isPresented: $isShowingDeleteAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .destructive(Text("Delete"), action: deleteActionClosure),
                secondaryButton: .cancel()
            )
        }
    }
    
    private var defaultModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default Model")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(whisperState.currentTranscriptionModel?.displayName ?? "No model selected")
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: false))
        .cornerRadius(10)
    }
    
    private var languageSelectionSection: some View {
        LanguageSelectionView(whisperState: whisperState, displayMode: .full, whisperPrompt: whisperPrompt)
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
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
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
            
            if isShowingSettings {
                ModelSettingsView(whisperPrompt: whisperPrompt)
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredModels, id: \.id) { model in
                        let isWarming = (model as? LocalModel).map { localModel in
                            warmupCoordinator.isWarming(modelNamed: localModel.name)
                        } ?? false

                        ModelCardRowView(
                            model: model,
                            whisperState: whisperState, 
                            isDownloaded: whisperState.availableModels.contains { $0.name == model.name },
                            isCurrent: whisperState.currentTranscriptionModel?.name == model.name,
                            downloadProgress: whisperState.downloadProgress,
                            modelURL: whisperState.availableModels.first { $0.name == model.name }?.url,
                            isWarming: isWarming,
                            deleteAction: {
                                if let customModel = model as? CustomCloudModel {
                                    alertTitle = "Delete Custom Model"
                                    alertMessage = "Are you sure you want to delete the custom model '\(customModel.displayName)'?"
                                    deleteActionClosure = {
                                        customModelManager.removeCustomModel(withId: customModel.id)
                                        whisperState.refreshAllAvailableModels()
                                    }
                                    isShowingDeleteAlert = true
                                } else if let senseVoiceModel = model as? SenseVoiceModel {
                                    alertTitle = "Delete Model"
                                    alertMessage = "Remove downloaded SenseVoice files for '\(senseVoiceModel.displayName)'?"
                                    deleteActionClosure = {
                                        whisperState.deleteSenseVoiceModel(senseVoiceModel)
                                    }
                                    isShowingDeleteAlert = true
                                } else if let downloadedModel = whisperState.availableModels.first(where: { $0.name == model.name }) {
                                    alertTitle = "Delete Model"
                                    alertMessage = "Are you sure you want to delete the model '\(downloadedModel.name)'?"
                                    deleteActionClosure = {
                                        Task {
                                            await whisperState.deleteModel(downloadedModel)
                                        }
                                    }
                                    isShowingDeleteAlert = true
                                }
                            },
                            setDefaultAction: {
                                Task {
                                    await whisperState.setDefaultTranscriptionModel(model)
                                }
                            },
                            downloadAction: {
                                if let localModel = model as? LocalModel {
                                    Task { await whisperState.downloadModel(localModel) }
                                } else if let senseVoiceModel = model as? SenseVoiceModel {
                                    Task { await whisperState.downloadSenseVoiceModel(senseVoiceModel) }
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
                                title: "Import local Whisper models",
                                message: "Add a custom fine-tuned whisper model to use with VoiceInk. Select the downloaded .bin file.",
                                learnMoreURL: "https://tryvoiceink.com/docs/custom-local-whisper-models"
                            )
                            .help("Read more about custom local models")
                        }
                    }
                    
                    if selectedFilter == .custom {
                        // Add Custom Model Card at the bottom
                        AddCustomModelCardView(
                            customModelManager: customModelManager,
                            editingModel: customModelToEdit
                        ) {
                            // Refresh the models when a new custom model is added
                            whisperState.refreshAllAvailableModels()
                            customModelToEdit = nil // Clear editing state
                        }
                    }
                }
            }
        }
        .padding()
    }

    private var filteredModels: [any TranscriptionModel] {
        switch selectedFilter {
        case .recommended:
            let recommendedNames = [
                "ggml-base.en",
                "ggml-large-v3-turbo-q5_0",
                "sensevoice-zh-en-ja-ko-yue",
                "parakeet-tdt-0.6b-v2",
                "parakeet-tdt-0.6b-v3"
            ]
            return whisperState.allAvailableModels.filter {
                recommendedNames.contains($0.name)
            }.sorted { model1, model2 in
                // Sort by: 1) Best balanced (fast + accurate) first, 2) Then by accuracy
                let score1 = modelRecommendationScore(model1)
                let score2 = modelRecommendationScore(model2)
                if abs(score1 - score2) > 0.01 {
                    return score1 > score2
                }
                // Tie-breaker: higher accuracy wins
                return model1.accuracy > model2.accuracy
            }
        case .local:
            return whisperState.allAvailableModels.filter { 
                $0.provider == .local || $0.provider == .nativeApple || $0.provider == .parakeet || $0.provider == .senseVoice 
            }.sorted { model1, model2 in
                let score1 = modelRecommendationScore(model1)
                let score2 = modelRecommendationScore(model2)
                if abs(score1 - score2) > 0.01 {
                    return score1 > score2
                }
                return model1.accuracy > model2.accuracy
            }
        case .cloud:
            let cloudProviders: [ModelProvider] = [.groq, .elevenLabs, .deepgram, .mistral, .gemini, .soniox]
            return whisperState.allAvailableModels.filter { cloudProviders.contains($0.provider) }
                .sorted { model1, model2 in
                    let score1 = modelRecommendationScore(model1)
                    let score2 = modelRecommendationScore(model2)
                    if abs(score1 - score2) > 0.01 {
                        return score1 > score2
                    }
                    return model1.accuracy > model2.accuracy
                }
        case .custom:
            return whisperState.allAvailableModels.filter { $0.provider == .custom }
        }
    }
    
    /// Calculates a recommendation score prioritizing models that are both fast AND accurate.
    private func modelRecommendationScore(_ model: any TranscriptionModel) -> Double {
        let accuracy = model.accuracy
        let speed = model.speed
        
        // Use geometric mean to reward models that excel at BOTH speed and accuracy
        let balancedScore = sqrt(accuracy * speed)
        
        // Boost for models that meet high thresholds in both categories
        let isHighAccuracy = accuracy >= 0.94
        let isHighSpeed = speed >= 0.75
        let bonus: Double = (isHighAccuracy && isHighSpeed) ? 0.1 : 0
        
        return balancedScore + bonus
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
                await whisperState.importLocalModel(from: url)
            }
        }
    }
}
