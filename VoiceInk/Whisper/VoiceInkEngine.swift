import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import KeyboardShortcuts
import os
import Combine

// MARK: - Recording State Machine
enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case transcribing
    case enhancing
    case busy
}

@MainActor
class VoiceInkEngine: NSObject, ObservableObject {
    // MARK: - Sub-managers
    let recordingCoordinator: RecordingCoordinator
    let recorderUI: RecorderUIManager
    let modelManager: ModelManager

    let modelContext: ModelContext
    let enhancementService: AIEnhancementService?
    internal var serviceRegistry: TranscriptionServiceRegistry!
    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VoiceInkEngine")

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Forwarding Published Properties (recording)

    @Published var recordingState: RecordingState = .idle

    // MARK: - Forwarding Published Properties (model)

    @Published var isModelLoaded = false
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var availableModels: [WhisperModel] = []
    @Published var allAvailableModels: [any TranscriptionModel] = PredefinedModels.models
    @Published var downloadProgress: [String: Double] = [:]

    // MARK: - Forwarding Published Properties (UI)

    @Published var recorderType: String = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini" {
        didSet {
            recorderUI.recorderType = recorderType
        }
    }
    @Published var isMiniRecorderVisible = false {
        didSet {
            recorderUI.isMiniRecorderVisible = isMiniRecorderVisible
        }
    }

    // MARK: - Forwarding Non-Published Properties

    var partialTranscript: String { recordingCoordinator.partialTranscript }

    var whisperContext: WhisperContext? { modelManager.whisperContext }

    var recorder: Recorder { recordingCoordinator.recorder }
    let whisperPrompt = WhisperPrompt()

    let modelsDirectory: URL
    let recordingsDirectory: URL

    // MARK: - Computed Properties

    var usableModels: [any TranscriptionModel] { modelManager.usableModels }

    // MARK: - Init

    init(modelContext: ModelContext, enhancementService: AIEnhancementService? = nil) {
        self.modelContext = modelContext
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")

        self.modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")
        self.enhancementService = enhancementService

        // Create sub-managers
        self.modelManager = ModelManager(modelsDirectory: self.modelsDirectory)
        self.recordingCoordinator = RecordingCoordinator(
            modelContext: modelContext,
            recordingsDirectory: self.recordingsDirectory,
            enhancementService: enhancementService
        )
        self.recorderUI = RecorderUIManager()

        super.init()

        // Wire cross-references
        recordingCoordinator.modelManager = modelManager
        recordingCoordinator.onDismissRecorder = { [weak self] in
            await self?.recorderUI.dismissMiniRecorder()
        }
        recorderUI.recordingCoordinator = recordingCoordinator
        recorderUI.engineFacade = self

        // Initialize service registry
        self.serviceRegistry = TranscriptionServiceRegistry(engine: self, modelsDirectory: self.modelsDirectory)
        recordingCoordinator.serviceRegistry = self.serviceRegistry

        // Configure PowerModeSessionManager
        if let enhancementService = enhancementService {
            PowerModeSessionManager.shared.configure(engine: self, enhancementService: enhancementService)
        }

        // Wire warmup callback — warmup coordinator needs VoiceInkEngine reference
        modelManager.whisperModelManager.onModelDownloaded = { [weak self] model in
            guard let self = self else { return }
            WhisperModelWarmupCoordinator.shared.scheduleWarmup(for: model, engine: self)
        }

        // Set up Combine forwarding: sub-manager changes -> facade @Published updates
        setupCombineForwarding()

        // Setup and load
        recorderUI.setupNotifications()
        modelManager.createModelsDirectoryIfNeeded()
        modelManager.loadAvailableModels()
        modelManager.loadCurrentTranscriptionModel()
        modelManager.refreshAllAvailableModels()

        // Sync initial state from sub-managers
        syncFromSubManagers()
    }

    // MARK: - Combine Forwarding

    private func setupCombineForwarding() {
        // Forward RecordingCoordinator changes
        recordingCoordinator.$recordingState
            .sink { [weak self] val in self?.recordingState = val }
            .store(in: &cancellables)

        // Forward ModelManager changes
        modelManager.$currentTranscriptionModel
            .sink { [weak self] val in self?.currentTranscriptionModel = val }
            .store(in: &cancellables)
        modelManager.$allAvailableModels
            .sink { [weak self] val in self?.allAvailableModels = val }
            .store(in: &cancellables)
        // Forward WhisperModelManager changes via ModelManager
        modelManager.whisperModelManager.$availableModels
            .sink { [weak self] val in self?.availableModels = val }
            .store(in: &cancellables)
        modelManager.whisperModelManager.$isModelLoaded
            .sink { [weak self] val in self?.isModelLoaded = val }
            .store(in: &cancellables)
        modelManager.whisperModelManager.$downloadProgress
            .combineLatest(modelManager.parakeetModelManager.$downloadProgress)
            .sink { [weak self] (whisperProgress, parakeetProgress) in
                var merged = whisperProgress
                for (key, value) in parakeetProgress {
                    merged[key] = value
                }
                self?.downloadProgress = merged
            }
            .store(in: &cancellables)
        // Forward RecorderUIManager changes
        recorderUI.$recorderType
            .dropFirst() // Skip initial value to avoid re-triggering didSet
            .sink { [weak self] val in
                guard let self = self, self.recorderType != val else { return }
                self.recorderType = val
            }
            .store(in: &cancellables)
        recorderUI.$isMiniRecorderVisible
            .sink { [weak self] val in
                guard let self = self, self.isMiniRecorderVisible != val else { return }
                self.isMiniRecorderVisible = val
            }
            .store(in: &cancellables)
    }

    private func syncFromSubManagers() {
        recordingState = recordingCoordinator.recordingState
        currentTranscriptionModel = modelManager.currentTranscriptionModel
        allAvailableModels = modelManager.allAvailableModels
        availableModels = modelManager.availableModels
        isModelLoaded = modelManager.isModelLoaded
        downloadProgress = modelManager.downloadProgress
    }

    // MARK: - Forwarding Methods (Recording)

    func toggleRecord(powerModeId: UUID? = nil) async {
        await recordingCoordinator.toggleRecord(powerModeId: powerModeId)
    }

    func getEnhancementService() -> AIEnhancementService? {
        return enhancementService
    }

    // MARK: - Forwarding Methods (UI)

    func toggleMiniRecorder(powerModeId: UUID? = nil) async {
        await recorderUI.toggleMiniRecorder(powerModeId: powerModeId)
    }

    func dismissMiniRecorder() async {
        await recorderUI.dismissMiniRecorder()
    }

    func resetOnLaunch() async {
        await recorderUI.resetOnLaunch()
    }

    func cancelRecording() async {
        await recorderUI.cancelRecording()
    }

    @objc public func handleToggleMiniRecorder() {
        recorderUI.handleToggleMiniRecorder()
    }

    // MARK: - Forwarding Methods (Model Management)

    func loadModel(_ model: WhisperModel) async throws {
        try await modelManager.loadModel(model)
    }

    func downloadModel(_ model: LocalModel) async {
        await modelManager.downloadModel(model)
    }

    func deleteModel(_ model: WhisperModel) async {
        let wasCurrentModel = currentTranscriptionModel?.name == model.name
        await modelManager.deleteModel(model)
        if wasCurrentModel {
            recordingCoordinator.recordingState = .idle
        }
    }

    func unloadModel() {
        modelManager.unloadModel()
        recordingCoordinator.recordedFile = nil
    }

    func cleanupModelResources() async {
        await modelManager.cleanupModelResources(serviceRegistry: serviceRegistry)
    }

    func importLocalModel(from sourceURL: URL) async {
        await modelManager.importLocalModel(from: sourceURL)
    }

    func clearCurrentTranscriptionModel() {
        modelManager.clearCurrentTranscriptionModel()
    }

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        modelManager.setDefaultTranscriptionModel(model)
    }

    func refreshAllAvailableModels() {
        modelManager.refreshAllAvailableModels()
    }

    // MARK: - Forwarding Methods (Parakeet)

    func downloadParakeetModel(_ model: ParakeetModel) async {
        await modelManager.downloadParakeetModel(model)
    }

    func deleteParakeetModel(_ model: ParakeetModel) {
        modelManager.deleteParakeetModel(model)
    }

    func showParakeetModelInFinder(_ model: ParakeetModel) {
        modelManager.showParakeetModelInFinder(model)
    }

    func isParakeetModelDownloaded(named modelName: String) -> Bool {
        modelManager.isParakeetModelDownloaded(named: modelName)
    }

    func isParakeetModelDownloaded(_ model: ParakeetModel) -> Bool {
        modelManager.isParakeetModelDownloaded(model)
    }

    func isParakeetModelDownloading(_ model: ParakeetModel) -> Bool {
        modelManager.isParakeetModelDownloading(model)
    }
}
