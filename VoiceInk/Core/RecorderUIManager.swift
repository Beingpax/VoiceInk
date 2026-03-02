import Foundation
import SwiftUI
import os

@MainActor
class RecorderUIManager: NSObject, ObservableObject {
    @Published var recorderType: String = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini" {
        didSet {
            guard recorderType != oldValue else { return }
            if isMiniRecorderVisible {
                if oldValue == "notch" {
                    notchWindowManager?.hide()
                    notchWindowManager = nil
                } else {
                    miniWindowManager?.hide()
                    miniWindowManager = nil
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    showRecorderPanel()
                }
            }
            UserDefaults.standard.set(recorderType, forKey: "RecorderType")
        }
    }

    @Published var isMiniRecorderVisible = false {
        didSet {
            guard isMiniRecorderVisible != oldValue else { return }
            DispatchQueue.main.async { [self] in
                if isMiniRecorderVisible {
                    showRecorderPanel()
                } else {
                    hideRecorderPanel()
                }
            }
        }
    }

    var notchWindowManager: NotchWindowManager?
    var miniWindowManager: MiniWindowManager?
    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "RecorderUIManager")

    weak var recordingCoordinator: RecordingCoordinator?
    /// Reference to facade for window manager initialization (they need VoiceInkEngine)
    weak var engineFacade: VoiceInkEngine?

    override init() {
        super.init()
    }

    // MARK: - Recorder Panel Management

    func showRecorderPanel() {
        guard let facade = engineFacade else { return }
        logger.notice("Showing \(self.recorderType, privacy: .public) recorder")
        if recorderType == "notch" {
            if notchWindowManager == nil {
                notchWindowManager = NotchWindowManager(engine: facade, recorder: facade.recorder)
            }
            notchWindowManager?.show()
        } else {
            if miniWindowManager == nil {
                miniWindowManager = MiniWindowManager(engine: facade, recorder: facade.recorder)
            }
            miniWindowManager?.show()
        }
    }

    func hideRecorderPanel() {
        if recorderType == "notch" {
            notchWindowManager?.hide()
        } else {
            miniWindowManager?.hide()
        }
    }

    // MARK: - Mini Recorder Management

    func toggleMiniRecorder(powerModeId: UUID? = nil) async {
        logger.notice("toggleMiniRecorder called – visible=\(self.isMiniRecorderVisible, privacy: .public), state=\(String(describing: self.recordingCoordinator?.recordingState), privacy: .public)")
        if isMiniRecorderVisible {
            if recordingCoordinator?.recordingState == .recording {
                logger.notice("toggleMiniRecorder: stopping recording (was recording)")
                await recordingCoordinator?.toggleRecord(powerModeId: powerModeId)
            } else {
                logger.notice("toggleMiniRecorder: cancelling (was not recording)")
                await cancelRecording()
            }
        } else {
            SoundManager.shared.playStartSound()

            await MainActor.run {
                isMiniRecorderVisible = true
            }

            await recordingCoordinator?.toggleRecord(powerModeId: powerModeId)
        }
    }

    func dismissMiniRecorder() async {
        logger.notice("dismissMiniRecorder called – state=\(String(describing: self.recordingCoordinator?.recordingState), privacy: .public)")
        guard let coordinator = recordingCoordinator else { return }

        if coordinator.recordingState == .busy {
            logger.notice("dismissMiniRecorder: early return, state is busy")
            return
        }

        let wasRecording = coordinator.recordingState == .recording

        await MainActor.run {
            coordinator.recordingState = .busy
        }

        coordinator.currentSession?.cancel()
        coordinator.currentSession = nil

        if wasRecording {
            await coordinator.recorder.stopRecording()
        }

        hideRecorderPanel()

        if let enhancementService = coordinator.enhancementService {
            await MainActor.run {
                enhancementService.clearCapturedContexts()
            }
        }

        await MainActor.run {
            isMiniRecorderVisible = false
        }

        await coordinator.cleanupModelResources()

        if UserDefaults.standard.bool(forKey: PowerModeDefaults.autoRestoreKey) {
            await PowerModeSessionManager.shared.endSession()
            await MainActor.run {
                PowerModeManager.shared.setActiveConfiguration(nil)
            }
        }

        await MainActor.run {
            coordinator.recordingState = .idle
        }
        logger.notice("dismissMiniRecorder completed")
    }

    func resetOnLaunch() async {
        logger.notice("Resetting recording state on launch")
        guard let coordinator = recordingCoordinator else { return }
        await coordinator.recorder.stopRecording()
        hideRecorderPanel()
        await MainActor.run {
            isMiniRecorderVisible = false
            coordinator.shouldCancelRecording = false
            coordinator.miniRecorderError = nil
            coordinator.recordingState = .idle
        }
        await coordinator.cleanupModelResources()
    }

    func cancelRecording() async {
        logger.notice("cancelRecording called")
        SoundManager.shared.playEscSound()
        recordingCoordinator?.shouldCancelRecording = true
        await dismissMiniRecorder()
    }

    // MARK: - Notification Handling

    func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleToggleMiniRecorder), name: .toggleMiniRecorder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDismissMiniRecorder), name: .dismissMiniRecorder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLicenseStatusChanged), name: .licenseStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePromptChange), name: .promptDidChange, object: nil)
    }

    @objc public func handleToggleMiniRecorder() {
        logger.notice("handleToggleMiniRecorder: .toggleMiniRecorder notification received")
        Task {
            await toggleMiniRecorder()
        }
    }

    @objc public func handleDismissMiniRecorder() {
        logger.notice("handleDismissMiniRecorder: .dismissMiniRecorder notification received")
        Task {
            await dismissMiniRecorder()
        }
    }

    @objc func handleLicenseStatusChanged() {
        recordingCoordinator?.licenseViewModel = LicenseViewModel()
    }

    @objc func handlePromptChange() {
        Task {
            await engineFacade?.modelManager.updateContextPrompt()
        }
    }
}
