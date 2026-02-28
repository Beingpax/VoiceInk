import Foundation
import SwiftUI

@MainActor
extension WhisperState {
    // Loads the default transcription model from UserDefaults
    func loadCurrentTranscriptionModel() {
        if let savedModelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel"),
           let savedModel = allAvailableModels.first(where: { $0.name == savedModelName }) {
            currentTranscriptionModel = savedModel
        }
    }

    // Function to set any transcription model as default
    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        self.currentTranscriptionModel = model
        UserDefaults.standard.set(model.name, forKey: "CurrentTranscriptionModel")

        // For cloud models, clear the old loadedLocalModel
        if model.provider != .local {
            self.loadedLocalModel = nil
        }

        // Enable transcription for cloud models immediately since they don't need loading
        if model.provider != .local {
            self.isModelLoaded = true
        }
        // Post notification about the model change
        NotificationCenter.default.post(name: .didChangeModel, object: nil, userInfo: ["modelName": model.name])
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)

        // Pre-load the model in background so it's ready when recording starts
        if recordingState == .idle {
            preloadModel(model)
        }
    }

    private func preloadModel(_ model: any TranscriptionModel) {
        Task.detached { [weak self] in
            guard let self else { return }
            switch model.provider {
            case .local:
                if let localModel = await self.availableModels.first(where: { $0.name == model.name }),
                   await self.whisperContext == nil {
                    // Release old context before loading new one
                    await self.whisperContext?.releaseResources()
                    await MainActor.run { self.whisperContext = nil }
                    try? await self.loadModel(localModel)
                }
            case .parakeet:
                if let parakeetModel = model as? ParakeetModel {
                    try? await self.serviceRegistry.parakeetTranscriptionService.loadModel(for: parakeetModel)
                }
            default:
                break
            }
        }
    }
    
    func refreshAllAvailableModels() {
        let currentModelName = currentTranscriptionModel?.name
        var models = PredefinedModels.models

        // Append dynamically discovered local models (imported .bin files) with minimal metadata
        for whisperModel in availableModels {
            if !models.contains(where: { $0.name == whisperModel.name }) {
                let importedModel = ImportedLocalModel(fileBaseName: whisperModel.name)
                models.append(importedModel)
            }
        }

        allAvailableModels = models

        // Preserve current selection by name (IDs may change for dynamic models)
        if let currentName = currentModelName,
           let updatedModel = allAvailableModels.first(where: { $0.name == currentName }) {
            setDefaultTranscriptionModel(updatedModel)
        }
    }
} 