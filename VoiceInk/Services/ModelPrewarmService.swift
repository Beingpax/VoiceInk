import Foundation
import SwiftData
import os
import AppKit
import IOKit.ps

@MainActor
final class ModelPrewarmService: ObservableObject {
    private let transcriptionModelManager: TranscriptionModelManager
    private let whisperModelManager: WhisperModelManager
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ModelPrewarm")
    private lazy var serviceRegistry = TranscriptionServiceRegistry(
        modelProvider: whisperModelManager,
        modelsDirectory: whisperModelManager.modelsDirectory,
        modelContext: modelContext
    )
    private let prewarmAudioURL = Bundle.main.url(forResource: "sound7", withExtension: "wav")
    private let prewarmEnabledKey = "PrewarmModelOnWake"
    private let keepAliveEnabledKey = "KeepModelAlive"
    private let keepAliveOnBatteryKey = "KeepModelAliveOnBattery"
    private let keepAliveInterval: TimeInterval = 5 * 60 // 5 minutes
    private var keepAliveTask: Task<Void, Never>?

    init(transcriptionModelManager: TranscriptionModelManager, whisperModelManager: WhisperModelManager, modelContext: ModelContext) {
        self.transcriptionModelManager = transcriptionModelManager
        self.whisperModelManager = whisperModelManager
        self.modelContext = modelContext
        setupNotifications()
        schedulePrewarmOnAppLaunch()
        startKeepAlive()
    }

    // MARK: - Notification Setup

    private func setupNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        // Trigger on wake from sleep
        center.addObserver(
            self,
            selector: #selector(schedulePrewarm),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        logger.notice("ModelPrewarmService initialized - listening for wake and app launch")
    }

    // MARK: - Trigger Handlers

    /// Trigger on app launch (cold start)
    private func schedulePrewarmOnAppLaunch() {
        logger.notice("App launched, scheduling prewarm")
        Task {
            try? await Task.sleep(for: .seconds(3))
            await performPrewarm()
        }
    }

    /// Trigger on wake from sleep or screen unlock
    @objc private func schedulePrewarm() {
        logger.notice("Mac activity detected (wake/unlock), scheduling prewarm")
        Task {
            try? await Task.sleep(for: .seconds(3))
            await performPrewarm()
        }
    }

    // MARK: - Core Prewarming Logic

    private func performPrewarm() async {
        guard shouldPrewarm() else { return }

        guard let audioURL = prewarmAudioURL else {
            logger.error("❌ Prewarm audio file (sound7.wav) not found")
            return
        }

        guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
            logger.notice("No model selected, skipping prewarm")
            return
        }

        logger.notice("Prewarming \(currentModel.displayName, privacy: .public)")
        let startTime = Date()

        do {
            let _ = try await serviceRegistry.transcribe(audioURL: audioURL, model: currentModel)
            let duration = Date().timeIntervalSince(startTime)

            logger.notice("Prewarm completed in \(String(format: "%.2f", duration), privacy: .public)s")

        } catch {
            logger.error("❌ Prewarm failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Validation

    private func shouldPrewarm() -> Bool {
        // Check if user has enabled prewarming
        let isEnabled = UserDefaults.standard.bool(forKey: prewarmEnabledKey)
        guard isEnabled else {
            logger.notice("Prewarm disabled by user")
            return false
        }

        // Only prewarm local models (Parakeet and Whisper need ANE compilation)
        guard let model = transcriptionModelManager.currentTranscriptionModel else {
            return false
        }

        switch model.provider {
        case .whisper, .fluidAudio:
            return true
        default:
            logger.notice("Skipping prewarm - cloud models don't need it")
            return false
        }
    }

    deinit {
        keepAliveTask?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.notice("ModelPrewarmService deinitialized")
    }

    // MARK: - Keep-Alive (prevents macOS from paging model memory after idle)

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        guard UserDefaults.standard.bool(forKey: keepAliveEnabledKey) else {
            logger.notice("Keep-alive disabled by user")
            return
        }
        let interval = keepAliveInterval
        let batteryKey = keepAliveOnBatteryKey
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { break }

                // Skip on battery unless explicitly allowed
                if !UserDefaults.standard.bool(forKey: batteryKey) && self.isOnBattery() {
                    self.logger.notice("Keep-alive skipped — on battery")
                    continue
                }

                // Skip if low power mode
                if ProcessInfo.processInfo.isLowPowerModeEnabled {
                    self.logger.notice("Keep-alive skipped — Low Power Mode")
                    continue
                }

                await self.performPrewarm()
            }
        }
        logger.notice("Keep-alive timer started (interval: \(Int(interval))s)")
    }

    private nonisolated func isOnBattery() -> Bool {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String?
        return type == kIOPSBatteryPowerValue
    }
}
