import Foundation
import SwiftUI
import Combine
import os

@MainActor
class ModelManager: ObservableObject {
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var allAvailableModels: [any TranscriptionModel] = PredefinedModels.models

    let whisperModelManager: WhisperModelManager
    let parakeetModelManager: ParakeetModelManager
    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ModelManager")

    private var cancellables = Set<AnyCancellable>()

    init(modelsDirectory: URL) {
        self.whisperModelManager = WhisperModelManager(modelsDirectory: modelsDirectory)
        self.parakeetModelManager = ParakeetModelManager()

        // Forward objectWillChange from sub-managers
        whisperModelManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        parakeetModelManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Wire callbacks
        whisperModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
        parakeetModelManager.onModelChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
    }

    // MARK: - Forwarded Properties

    var availableModels: [WhisperModel] {
        get { whisperModelManager.availableModels }
        set { whisperModelManager.availableModels = newValue }
    }

    var isModelLoaded: Bool {
        get { whisperModelManager.isModelLoaded }
        set { whisperModelManager.isModelLoaded = newValue }
    }

    var loadedLocalModel: WhisperModel? {
        get { whisperModelManager.loadedLocalModel }
        set { whisperModelManager.loadedLocalModel = newValue }
    }

    var whisperContext: WhisperContext? {
        get { whisperModelManager.whisperContext }
        set { whisperModelManager.whisperContext = newValue }
    }

    var modelsDirectory: URL {
        whisperModelManager.modelsDirectory
    }

    var downloadProgress: [String: Double] {
        get {
            var merged = whisperModelManager.downloadProgress
            for (key, value) in parakeetModelManager.downloadProgress {
                merged[key] = value
            }
            return merged
        }
        set {
            whisperModelManager.downloadProgress = newValue
        }
    }

    var parakeetDownloadStates: [String: Bool] {
        get { parakeetModelManager.parakeetDownloadStates }
        set { parakeetModelManager.parakeetDownloadStates = newValue }
    }

    var usableModels: [any TranscriptionModel] {
        allAvailableModels.filter { model in
            switch model.provider {
            case .local:
                return whisperModelManager.availableModels.contains { $0.name == model.name }
            case .parakeet:
                return parakeetModelManager.isParakeetModelDownloaded(named: model.name)
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

    // MARK: - Model Selection

    func loadCurrentTranscriptionModel() {
        if let savedModelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel"),
           let savedModel = allAvailableModels.first(where: { $0.name == savedModelName }) {
            currentTranscriptionModel = savedModel
        }
    }

    func clearCurrentTranscriptionModel() {
        currentTranscriptionModel = nil
        UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
    }

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        self.currentTranscriptionModel = model
        UserDefaults.standard.set(model.name, forKey: "CurrentTranscriptionModel")

        if model.provider != .local {
            whisperModelManager.loadedLocalModel = nil
        }

        if model.provider != .local {
            whisperModelManager.isModelLoaded = true
        }

        NotificationCenter.default.post(name: .didChangeModel, object: nil, userInfo: ["modelName": model.name])
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    func refreshAllAvailableModels() {
        let currentModelName = currentTranscriptionModel?.name
        var models = PredefinedModels.models

        for whisperModel in whisperModelManager.availableModels {
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

    // MARK: - Forwarded Whisper Model Methods

    func loadModel(_ model: WhisperModel) async throws {
        try await whisperModelManager.loadModel(model)
    }

    func downloadModel(_ model: LocalModel) async {
        await whisperModelManager.downloadModel(model)
    }

    func deleteModel(_ model: WhisperModel) async {
        let didClear = await whisperModelManager.deleteModel(model, currentTranscriptionModelName: currentTranscriptionModel?.name)
        if didClear {
            currentTranscriptionModel = nil
            UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
            UserDefaults.standard.removeObject(forKey: "CurrentModel")
        }
        refreshAllAvailableModels()
    }

    func unloadModel() {
        whisperModelManager.unloadModel()
    }

    func cleanupModelResources(serviceRegistry: TranscriptionServiceRegistry?) async {
        await whisperModelManager.cleanupModelResources(serviceRegistry: serviceRegistry)
    }

    func importLocalModel(from sourceURL: URL) async {
        await whisperModelManager.importLocalModel(from: sourceURL)
    }

    func createModelsDirectoryIfNeeded() {
        whisperModelManager.createModelsDirectoryIfNeeded()
    }

    func loadAvailableModels() {
        whisperModelManager.loadAvailableModels()
    }

    func updateContextPrompt() async {
        await whisperModelManager.updateContextPrompt()
    }

    // MARK: - Forwarded Parakeet Methods

    func downloadParakeetModel(_ model: ParakeetModel) async {
        await parakeetModelManager.downloadParakeetModel(model)
    }

    func deleteParakeetModel(_ model: ParakeetModel) {
        parakeetModelManager.deleteParakeetModel(model)
        if let currentModel = currentTranscriptionModel,
           currentModel.provider == .parakeet,
           currentModel.name == model.name {
            currentTranscriptionModel = nil
            UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
        }
        refreshAllAvailableModels()
    }

    func showParakeetModelInFinder(_ model: ParakeetModel) {
        parakeetModelManager.showParakeetModelInFinder(model)
    }

    func isParakeetModelDownloaded(named modelName: String) -> Bool {
        parakeetModelManager.isParakeetModelDownloaded(named: modelName)
    }

    func isParakeetModelDownloaded(_ model: ParakeetModel) -> Bool {
        parakeetModelManager.isParakeetModelDownloaded(model)
    }

    func isParakeetModelDownloading(_ model: ParakeetModel) -> Bool {
        parakeetModelManager.isParakeetModelDownloading(model)
    }
}
