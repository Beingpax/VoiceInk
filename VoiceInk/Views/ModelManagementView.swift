import SwiftUI
import SwiftData

struct ModelManagementView: View {
    @ObservedObject var whisperState: WhisperState
    @State private var modelToDelete: WhisperModel?
    @StateObject private var aiService = AIService()
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext
    @StateObject private var whisperPrompt = WhisperPrompt()
    @ObservedObject private var audioManager = AudioTranscriptionManager.shared // Added
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                cloudServiceToggleSection // Added
                defaultModelSection
                    .disabled(audioManager.useCloudService)
                    .opacity(audioManager.useCloudService ? 0.5 : 1.0)
                languageSelectionSection
                    .disabled(audioManager.useCloudService)
                    .opacity(audioManager.useCloudService ? 0.5 : 1.0)
                availableModelsSection
                    .disabled(audioManager.useCloudService)
                    .opacity(audioManager.useCloudService ? 0.5 : 1.0)
            }
            .padding(40)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .alert(item: $modelToDelete) { model in
            Alert(
                title: Text("Delete Model"),
                message: Text("Are you sure you want to delete the model '\(model.name)'?"),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        await whisperState.deleteModel(model)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private var defaultModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default Model")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(whisperState.currentModel.flatMap { model in
                PredefinedModels.models.first { $0.name == model.name }?.displayName
            } ?? "No model selected")
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .cornerRadius(10)
    }

    private var cloudServiceToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcription Source")
                .font(.headline)
                .foregroundColor(.secondary)

            Toggle("Use Cloud Transcription Service", isOn: $audioManager.useCloudService)
                .toggleStyle(.switch)
                .padding(.vertical, 4)

            Text(audioManager.useCloudService ? "Cloud transcription is active. Local models are disabled." : "Local models are active. Turn on to use cloud-based transcription.")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .cornerRadius(10)
    }
    
    private var languageSelectionSection: some View {
        LanguageSelectionView(whisperState: whisperState, displayMode: .full, whisperPrompt: whisperPrompt)
    }
    
    private var availableModelsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Available Models")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("(\(whisperState.predefinedModels.count))")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                ForEach(whisperState.predefinedModels) { model in
                    ModelCardRowView(
                        model: model,
                        isDownloaded: whisperState.availableModels.contains { $0.name == model.name },
                        isCurrent: whisperState.currentModel?.name == model.name,
                        downloadProgress: whisperState.downloadProgress,
                        modelURL: whisperState.availableModels.first { $0.name == model.name }?.url,
                        deleteAction: {
                            if let downloadedModel = whisperState.availableModels.first(where: { $0.name == model.name }) {
                                modelToDelete = downloadedModel
                            }
                        },
                        setDefaultAction: {
                            if let downloadedModel = whisperState.availableModels.first(where: { $0.name == model.name }) {
                                Task {
                                    await whisperState.setDefaultModel(downloadedModel)
                                }
                            }
                        },
                        downloadAction: {
                            Task {
                                await whisperState.downloadModel(model)
                            }
                        }
                    )
                }
            }
        }
        .padding()
    }
}
