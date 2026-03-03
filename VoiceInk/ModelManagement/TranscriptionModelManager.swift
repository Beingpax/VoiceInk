import Foundation
import SwiftUI
import os

@MainActor
class TranscriptionModelManager: ObservableObject {
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var allAvailableModels: [any TranscriptionModel] = PredefinedModels.models

    private weak var whisperModelManager: WhisperModelManager?
    private weak var parakeetModelManager: ParakeetModelManager?

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionModelManager")

    init(whisperModelManager: WhisperModelManager, parakeetModelManager: ParakeetModelManager) {
        self.whisperModelManager = whisperModelManager
        self.parakeetModelManager = parakeetModelManager

        // Wire up deletion callbacks so each manager notifies this manager.
        whisperModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }
        parakeetModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }

        // Wire up "models changed" callbacks so this manager rebuilds allAvailableModels.
        whisperModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
        parakeetModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
    }

    // MARK: - Computed: usable models

    var usableModels: [any TranscriptionModel] {
        allAvailableModels.filter { model in
            switch model.provider {
            case .local:
                return whisperModelManager?.availableModels.contains { $0.name == model.name } ?? false
            case .parakeet:
                return parakeetModelManager?.isParakeetModelDownloaded(named: model.name) ?? false
            case .nativeApple:
                if #available(macOS 26, *) {
                    return true
                } else {
                    return false
                }
            case .groq:
                return APIKeyManager.shared.hasAPIKey(forProvider: "Groq")
            case .elevenLabs:
                return APIKeyManager.shared.hasAPIKey(forProvider: "ElevenLabs")
            case .deepgram:
                return APIKeyManager.shared.hasAPIKey(forProvider: "Deepgram")
            case .mistral:
                return APIKeyManager.shared.hasAPIKey(forProvider: "Mistral")
            case .gemini:
                return APIKeyManager.shared.hasAPIKey(forProvider: "Gemini")
            case .soniox:
                return APIKeyManager.shared.hasAPIKey(forProvider: "Soniox")
            case .custom:
                return true
            }
        }
    }

    // MARK: - Model loading from UserDefaults

    func loadCurrentTranscriptionModel() {
        if let savedModelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel"),
           let savedModel = allAvailableModels.first(where: { $0.name == savedModelName }) {
            currentTranscriptionModel = savedModel
        }
    }

    // MARK: - Set default model

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        self.currentTranscriptionModel = model
        UserDefaults.standard.set(model.name, forKey: "CurrentTranscriptionModel")

        if model.provider != .local {
            whisperModelManager?.loadedLocalModel = nil
            whisperModelManager?.isModelLoaded = true
        }

        NotificationCenter.default.post(name: .didChangeModel, object: nil, userInfo: ["modelName": model.name])
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    // MARK: - Refresh all available models

    func refreshAllAvailableModels() {
        let currentModelName = currentTranscriptionModel?.name
        var models = PredefinedModels.models

        for whisperModel in whisperModelManager?.availableModels ?? [] {
            if !models.contains(where: { $0.name == whisperModel.name }) {
                let importedModel = ImportedLocalModel(fileBaseName: whisperModel.name)
                models.append(importedModel)
            }
        }

        allAvailableModels = models

        if let currentName = currentModelName,
           let updatedModel = allAvailableModels.first(where: { $0.name == currentName }) {
            setDefaultTranscriptionModel(updatedModel)
        }
    }

    // MARK: - Clear current model

    func clearCurrentTranscriptionModel() {
        currentTranscriptionModel = nil
        UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
    }

    // MARK: - Handle model deletion callback

    /// Called by WhisperModelManager.onModelDeleted or ParakeetModelManager.onModelDeleted.
    func handleModelDeleted(_ modelName: String) {
        if currentTranscriptionModel?.name == modelName {
            currentTranscriptionModel = nil
            UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
            whisperModelManager?.loadedLocalModel = nil
            whisperModelManager?.isModelLoaded = false
            UserDefaults.standard.removeObject(forKey: "CurrentModel")
        }
        refreshAllAvailableModels()
    }
}
