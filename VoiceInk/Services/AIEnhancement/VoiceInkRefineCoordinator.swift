import Foundation
import os

@MainActor
final class VoiceInkRefineCoordinator {
    private weak var enhancementService: AIEnhancementService?
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "VoiceInkRefineCoordinator"
    )

    private var activeSessionID: UUID?
    private var taskTokensByModel: [String: UUID] = [:]
    private var tasksByToken: [UUID: Task<Void, Never>] = [:]
    private var notificationObservers: [NSObjectProtocol] = []

    init(enhancementService: AIEnhancementService?) {
        self.enhancementService = enhancementService
        observeConfigurationChanges()
    }

    deinit {
        notificationObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        tasksByToken.values.forEach { $0.cancel() }
    }

    func start(sessionID: UUID) {
        if let previousSessionID = activeSessionID,
            previousSessionID != sessionID
        {
            cancelTasks()
            releaseInBackground(previousSessionID)
        }

        activeSessionID = sessionID
        prepareIfNeeded()
    }

    func finish() async {
        guard let sessionID = activeSessionID else { return }

        activeSessionID = nil
        cancelTasks()

        if let aiService = enhancementService?.getAIService() {
            await aiService.releaseVoiceInkRefineRecordingSession(sessionID)
        }
    }

    private func prepareIfNeeded() {
        guard let sessionID = activeSessionID,
            let enhancementService,
            let aiService = enhancementService.getAIService()
        else {
            return
        }

        let configuration = ModeRuntimeResolver.currentEnhancementConfiguration(
            enhancementService: enhancementService,
            aiService: aiService
        )
        guard configuration.isEnabled,
            configuration.provider == .voiceInkRefine,
            let modelID = configuration.modelName,
            taskTokensByModel[modelID] == nil
        else {
            return
        }

        let taskToken = UUID()
        taskTokensByModel[modelID] = taskToken
        tasksByToken[taskToken] = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await aiService.preloadVoiceInkRefineModelIfDownloaded(
                    modelID,
                    recordingSessionID: sessionID
                )
            } catch is CancellationError {
                // Finishing a recording cancels orchestration without waiting for MLX work.
            } catch {
                self.logger.error(
                    "VoiceInk Refine background preparation failed: \(error, privacy: .public)"
                )
            }

            guard self.taskTokensByModel[modelID] == taskToken else { return }
            self.taskTokensByModel[modelID] = nil
            self.tasksByToken[taskToken] = nil
        }
    }

    private func cancelTasks() {
        tasksByToken.values.forEach { $0.cancel() }
        tasksByToken.removeAll()
        taskTokensByModel.removeAll()
    }

    private func releaseInBackground(_ sessionID: UUID) {
        guard let aiService = enhancementService?.getAIService() else { return }
        Task(priority: .utility) {
            await aiService.releaseVoiceInkRefineRecordingSession(sessionID)
        }
    }

    private func observeConfigurationChanges() {
        let names: [Notification.Name] = [
            .activeModeDidChange,
            .modeConfigurationsDidChange,
            .AppSettingsDidChange,
        ]

        notificationObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.prepareIfNeeded()
                }
            }
        }
    }
}
