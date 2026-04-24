import Foundation
import SwiftUI
import os

@MainActor
class TranscriptionModelManager: ObservableObject {
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var currentMeetingsTranscriptionModel: (any TranscriptionModel)?
    @Published var allAvailableModels: [any TranscriptionModel] = TranscriptionModelRegistry.models

    private weak var whisperModelManager: WhisperModelManager?
    private weak var fluidAudioModelManager: FluidAudioModelManager?
    private weak var serviceRegistry: TranscriptionServiceRegistry?

    private let meetingsModelDefaultsKey = "CurrentMeetingsTranscriptionModel"

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionModelManager")

    init(whisperModelManager: WhisperModelManager, fluidAudioModelManager: FluidAudioModelManager) {
        self.whisperModelManager = whisperModelManager
        self.fluidAudioModelManager = fluidAudioModelManager

        // Wire up deletion callbacks so each manager notifies this manager.
        whisperModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }
        fluidAudioModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }

        // Wire up "models changed" callbacks so this manager rebuilds allAvailableModels.
        whisperModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
        fluidAudioModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
    }

    // MARK: - Registry injection

    func configure(registry: TranscriptionServiceRegistry) {
        self.serviceRegistry = registry
    }

    // MARK: - Computed: usable models

    var usableModels: [any TranscriptionModel] {
        allAvailableModels.filter { model in
            switch model.provider {
            case .whisper:
                return whisperModelManager?.availableModels.contains { $0.name == model.name } ?? false
            case .fluidAudio:
                return fluidAudioModelManager?.isFluidAudioModelDownloaded(named: model.name) ?? false
            case .nativeApple:
                if #available(macOS 26, *) { return true } else { return false }
            case .custom:
                return true
            default:
                if let cloudProvider = CloudProviderRegistry.provider(for: model.provider) {
                    return APIKeyManager.shared.hasAPIKey(forProvider: cloudProvider.providerKey)
                }
                return false
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

    // MARK: - Meetings transcription model

    func loadCurrentMeetingsTranscriptionModel() {
        guard let name = UserDefaults.standard.string(forKey: meetingsModelDefaultsKey) else { return }
        if let model = allAvailableModels.first(where: { $0.name == name }) {
            currentMeetingsTranscriptionModel = model
        }
    }

    func setMeetingsTranscriptionModel(_ model: any TranscriptionModel) {
        currentMeetingsTranscriptionModel = model
        UserDefaults.standard.set(model.name, forKey: meetingsModelDefaultsKey)
    }

    func clearMeetingsTranscriptionModel() {
        currentMeetingsTranscriptionModel = nil
        UserDefaults.standard.removeObject(forKey: meetingsModelDefaultsKey)
    }

    /// Models appropriate for offline file transcription (Meetings).
    /// Hides streaming-only variants: any model whose effectiveBatchModel differs from itself
    /// has a separate batch fallback listed — we hide the streaming variant to avoid confusion.
    var meetingsEligibleModels: [any TranscriptionModel] {
        guard let registry = serviceRegistry else {
            // Registry not yet injected; fall back to all usable models.
            return usableModels
        }
        return usableModels.filter { model in
            let effective = registry.effectiveBatchModel(for: model)
            return effective.name == model.name
        }
    }

    // MARK: - Set default model

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        self.currentTranscriptionModel = model
        UserDefaults.standard.set(model.name, forKey: "CurrentTranscriptionModel")

        if model.provider != .whisper {
            whisperModelManager?.loadedWhisperModel = nil
            whisperModelManager?.isModelLoaded = true
        }

        NotificationCenter.default.post(name: .didChangeModel, object: nil, userInfo: ["modelName": model.name])
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    // MARK: - Refresh all available models

    func refreshAllAvailableModels() {
        let currentModelName = currentTranscriptionModel?.name
        var models = TranscriptionModelRegistry.models

        for whisperModel in whisperModelManager?.availableModels ?? [] {
            if !models.contains(where: { $0.name == whisperModel.name }) {
                let importedModel = ImportedWhisperModel(fileBaseName: whisperModel.name)
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

    /// Called by WhisperModelManager.onModelDeleted or FluidAudioModelManager.onModelDeleted.
    func handleModelDeleted(_ modelName: String) {
        if currentTranscriptionModel?.name == modelName {
            currentTranscriptionModel = nil
            UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
            whisperModelManager?.loadedWhisperModel = nil
            whisperModelManager?.isModelLoaded = false
            UserDefaults.standard.removeObject(forKey: "CurrentModel")
        }
        if currentMeetingsTranscriptionModel?.name == modelName {
            clearMeetingsTranscriptionModel()
        }
        refreshAllAvailableModels()
    }
}
