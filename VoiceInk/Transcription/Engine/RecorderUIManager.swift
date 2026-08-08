import Foundation
import SwiftUI
import os

enum RecorderPanelStyle: String, CaseIterable, Identifiable {
    case notch
    case mini
    /// No panel — the display border carries state. See AmbientRecorderView.
    case ambient

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notch:
            return String(localized: "Notch")
        case .mini:
            return String(localized: "Mini")
        case .ambient:
            return String(localized: "Ambient")
        }
    }

    static var stored: RecorderPanelStyle {
        let rawValue = UserDefaults.standard.string(forKey: "RecorderType") ?? RecorderPanelStyle.mini.rawValue
        return RecorderPanelStyle(rawValue: rawValue) ?? .mini
    }
}

@MainActor
protocol RecorderPanelPresenting: AnyObject {
    var isRecorderPanelVisible: Bool { get }
    func dismissRecorderPanel() async
    /// Re-presents the panel after delivery has dismissed it, so it can carry the result peek.
    func presentPanelForResult()
    /// Stops the take in progress, as if the shortcut had been pressed again.
    func toggleRecorderPanel(modeId: UUID?) async
}

@MainActor
@Observable
class RecorderUIManager: RecorderPanelPresenting {
    var recorderPanelStyle: RecorderPanelStyle = .stored {
        didSet {
            guard oldValue != recorderPanelStyle else { return }
            rebuildVisiblePanel(previousStyle: oldValue)
            UserDefaults.standard.set(recorderPanelStyle.rawValue, forKey: "RecorderType")
        }
    }

    var recorderType: String {
        get { recorderPanelStyle.rawValue }
        set { recorderPanelStyle = RecorderPanelStyle(rawValue: newValue) ?? .mini }
    }

    var isRecorderPanelVisible = false {
        didSet {
            guard oldValue != isRecorderPanelVisible else { return }

            if isRecorderPanelVisible {
                showRecorderPanel()
            } else {
                hideRecorderPanel()
            }
        }
    }

    private var notchWindowManager: NotchWindowManager?
    private var ambientWindowManager: AmbientWindowManager?
    private var miniWindowManager: MiniWindowManager?

    private weak var engine: VoiceInkEngine?
    private var recorder: Recorder?

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "RecorderUIManager")

    init() {}

    /// Call after VoiceInkEngine is created to break the circular init dependency.
    func configure(engine: VoiceInkEngine, recorder: Recorder) {
        self.engine = engine
        self.recorder = recorder
        setupNotifications()
    }

    // MARK: - Recorder Panel Management

    /// Re-presents the panel to carry the result peek after delivery has dismissed it.
    func presentPanelForResult() {
        showRecorderPanel()
    }

    private func showRecorderPanel() {
        guard let engine = engine, let recorder = recorder else { return }

        switch recorderPanelStyle {
        case .notch:
            if notchWindowManager == nil {
                notchWindowManager = NotchWindowManager(
                    engine: engine,
                    recorder: recorder,
                    assistantSession: engine.assistantSession,
                    onRecordButtonTapped: { [weak self] in
                        Task { @MainActor in
                            await self?.toggleRecorderPanel()
                        }
                    },
                    onCloseTapped: { [weak self] in
                        Task { @MainActor in
                            await self?.dismissRecorderPanel()
                        }
                    },
                    onAssistantFollowUp: { [weak engine] text in
                        Task { @MainActor in
                            await engine?.sendAssistantFollowUp(text)
                        }
                    }
                )
            }
            notchWindowManager?.show()
        case .mini:
            if miniWindowManager == nil {
                miniWindowManager = MiniWindowManager(
                    engine: engine,
                    recorder: recorder,
                    assistantSession: engine.assistantSession,
                    onRecordButtonTapped: { [weak self] in
                        Task { @MainActor in
                            await self?.toggleRecorderPanel()
                        }
                    },
                    onCloseTapped: { [weak self] in
                        Task { @MainActor in
                            await self?.dismissRecorderPanel()
                        }
                    },
                    onAssistantFollowUp: { [weak engine] text in
                        Task { @MainActor in
                            await engine?.sendAssistantFollowUp(text)
                        }
                    }
                )
            }
            miniWindowManager?.show()

        case .ambient:
            if ambientWindowManager == nil {
                ambientWindowManager = AmbientWindowManager(engine: engine, recorder: recorder)
            }
            ambientWindowManager?.show()
        }
    }

    private func hideRecorderPanel() {
        switch recorderPanelStyle {
        case .notch:
            notchWindowManager?.hide()
        case .mini:
            miniWindowManager?.hide()
        case .ambient:
            ambientWindowManager?.hide()
        }
    }

    private func rebuildVisiblePanel(previousStyle: RecorderPanelStyle) {
        // Torn down whether or not it was on screen. A hidden window is not an inert one — the
        // ambient panel keeps a watchdog running to survive display changes, and leaving that alive
        // after switching to Mini left a full-screen window forcing itself to the front once a
        // second, swallowing clicks across the whole machine.
        switch previousStyle {
        case .notch:
            notchWindowManager?.destroyWindow()
            notchWindowManager = nil
        case .mini:
            miniWindowManager?.destroyWindow()
            miniWindowManager = nil
        case .ambient:
            ambientWindowManager?.destroyWindow()
            ambientWindowManager = nil
        }

        guard isRecorderPanelVisible else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            showRecorderPanel()
        }
    }

    // MARK: - Recorder Panel Management

    func toggleRecorderPanel(modeId: UUID? = nil) async {
        guard let engine = engine else { return }

        if isRecorderPanelVisible {
            switch engine.recordingState {
            case .recording:
                await engine.toggleRecord(modeId: modeId)
            case .starting, .transcribing, .enhancing:
                await cancelRecording()
            case .idle:
                if engine.assistantSession.canSendFollowUp {
                    SoundManager.shared.playStartSound()
                    await engine.toggleRecord(
                        modeId: modeId,
                        isAssistantFollowUp: true
                    )
                } else {
                    await dismissRecorderPanel()
                }
            case .busy:
                await dismissRecorderPanel()
            }
        } else {
            SoundManager.shared.playStartSound()
            isRecorderPanelVisible = true
            await engine.toggleRecord(modeId: modeId)
        }
    }

    func dismissRecorderPanel() async {
        guard let engine = engine else { return }

        hideRecorderPanel()
        isRecorderPanelVisible = false
        engine.assistantSession.reset()
    }

    func resetOnLaunch() async {
        guard let engine = engine else { return }
        logger.notice("Resetting recording state on launch")
        await engine.resetRecordingSession()
        hideRecorderPanel()
        isRecorderPanelVisible = false
        engine.assistantSession.reset()
    }

    func cancelRecording() async {
        guard let engine = engine else { return }
        await engine.cancelRecording()
        await dismissRecorderPanel()
    }

    // MARK: - Notification Handling

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleRecorderPanelNotification),
            name: .toggleRecorderPanel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissRecorderPanelNotification),
            name: .dismissRecorderPanel,
            object: nil
        )
    }

    @objc public func handleToggleRecorderPanelNotification() {
        Task {
            await toggleRecorderPanel()
        }
    }

    @objc public func handleDismissRecorderPanelNotification() {
        Task {
            switch engine?.recordingState {
            case .starting, .recording, .transcribing, .enhancing:
                await cancelRecording()
            case .idle, .busy, nil:
                await dismissRecorderPanel()
            }
        }
    }
}
