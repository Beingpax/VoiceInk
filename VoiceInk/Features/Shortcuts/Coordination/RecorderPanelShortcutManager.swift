import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class RecorderPanelShortcutManager: ObservableObject {
    private var recorderUIManager: RecorderUIManager
    private var visibilityTask: Task<Void, Never>?
    private var shortcutChangeObserver: NSObjectProtocol?
    private var settingsChangeObserver: NSObjectProtocol?
    private var recordingStateCancellable: AnyCancellable?
    private var observedSendKey: FinishAndSendKey
    private let visibleRecorderMonitor = ShortcutMonitor()

    // Double-tap Escape handling
    private var firstEscapePressTime: Date? = nil
    private let escapeDoublePressThreshold: TimeInterval = 1.5
    private var escapeTimeoutTask: Task<Void, Never>?
    private var activeEscapePressID: UUID?
    private var isEscapeConfirmationHintVisible = false

    private static let escapeConfirmationHintShownKey = "hasShownEscapeCancelConfirmationHint"

    static func resetEscapeConfirmationHint() {
        UserDefaults.standard.removeObject(forKey: escapeConfirmationHintShownKey)
    }

    init(recorderUIManager: RecorderUIManager) {
        self.recorderUIManager = recorderUIManager
        self.observedSendKey = FinishAndSendSettings.selectedKey
        setupShortcutChangeObserver()
        settingsChangeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let sendKey = FinishAndSendSettings.selectedKey
                guard sendKey != self.observedSendKey else { return }
                self.observedSendKey = sendKey
                self.refreshVisibleShortcuts()
            }
        }
        setupVisibilityObserver()
        recordingStateCancellable = recorderUIManager.recordingStatePublisher?.sink { [weak self] _ in
            Task { @MainActor in self?.refreshVisibleShortcuts() }
        }
    }

    private func setupShortcutChangeObserver() {
        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let action = notification.object as? ShortcutAction,
                action == .cancelRecorder
            else {
                return
            }

            Task { @MainActor in
                self?.resetEscapeState()
                self?.refreshVisibleShortcuts()
            }
        }
    }

    private func setupVisibilityObserver() {
        visibilityTask = Task { @MainActor in
            for await isVisible in recorderUIManager.$isRecorderPanelVisible.values {
                if isVisible {
                    refreshVisibleShortcuts()
                } else {
                    visibleRecorderMonitor.stop()
                    resetEscapeState()
                }
            }
        }
    }

    private var canUseModeShortcuts: Bool {
        !ModeManager.shared.enabledConfigurations.isEmpty
    }

    private func resetEscapeState() {
        firstEscapePressTime = nil
        activeEscapePressID = nil
        escapeTimeoutTask?.cancel()
        escapeTimeoutTask = nil

        if isEscapeConfirmationHintVisible {
            isEscapeConfirmationHintVisible = false
            NotificationManager.shared.dismissNotification()
        }
    }

    private func refreshVisibleShortcuts() {
        guard recorderUIManager.isRecorderPanelVisible else {
            visibleRecorderMonitor.stop()
            resetEscapeState()
            return
        }

        var shortcuts = ShortcutStore.shortcuts(for: ShortcutAction.recorderPanelStoredActions)

        if ShortcutStore.shortcut(for: .cancelRecorder) == nil {
            shortcuts[.recorderPanelEscape] = .key(keyCode: UInt16(kVK_Escape), modifierFlags: [])
        }

        if FinishAndSendSettings.selectedKey.isEnabled && recorderUIManager.isActivelyRecording {
            shortcuts[.recorderPanelReturn] = .key(keyCode: UInt16(kVK_Return), modifierFlags: [])
        }

        if canUseModeShortcuts {
            for (index, keyCode) in Self.digitKeyCodes.enumerated() {
                shortcuts[.recorderPanelMode(index)] = .key(
                    keyCode: keyCode,
                    modifierFlags: [.option]
                )
            }
        }

        visibleRecorderMonitor.start(
            shortcuts: shortcuts,
            onShortcutDown: { [weak self] action, _ in
                Task { @MainActor in
                    await self?.handleRecorderPanelShortcut(action)
                }
            },
            onShortcutUp: { _, _ in }
        )
    }

    private func handleRecorderPanelShortcut(_ action: ShortcutAction) async {
        guard recorderUIManager.isRecorderPanelVisible else { return }

        switch action {
        case .cancelRecorder:
            guard ShortcutStore.shortcut(for: .cancelRecorder) != nil else { return }
            await recorderUIManager.cancelRecording()
        case .recorderPanelEscape:
            await handleEscapeShortcut()
        case .recorderPanelReturn:
            if FinishAndSendSettings.selectedKey.isEnabled {
                await recorderUIManager.finishRecordingAndSend()
            }
        case .recorderPanelMode(let index):
            handleModeSelectionShortcut(index: index)
        default:
            break
        }
    }

    private func handleEscapeShortcut() async {
        guard ShortcutStore.shortcut(for: .cancelRecorder) == nil else { return }

        let now = Date()
        if let firstTime = firstEscapePressTime,
            now.timeIntervalSince(firstTime) <= escapeDoublePressThreshold
        {
            resetEscapeState()
            await recorderUIManager.cancelRecording()
            return
        }

        let escapePressID = UUID()
        firstEscapePressTime = now
        activeEscapePressID = escapePressID
        showEscapeConfirmationHintIfNeeded()
        escapeTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64((self?.escapeDoublePressThreshold ?? 1.5) * 1_000_000_000)
                )
            } catch {
                return
            }

            await MainActor.run {
                guard self?.activeEscapePressID == escapePressID else { return }
                self?.firstEscapePressTime = nil
                self?.activeEscapePressID = nil
                self?.escapeTimeoutTask = nil
                self?.isEscapeConfirmationHintVisible = false
            }
        }
    }

    private func showEscapeConfirmationHintIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.escapeConfirmationHintShownKey) else { return }

        defaults.set(true, forKey: Self.escapeConfirmationHintShownKey)
        isEscapeConfirmationHintVisible = true
        NotificationManager.shared.showNotification(
            title: String(localized: "Press Esc again to cancel"),
            type: .info,
            duration: escapeDoublePressThreshold
        )
    }

    private func handleModeSelectionShortcut(index: Int) {
        guard canUseModeShortcuts else { return }

        let modeManager = ModeManager.shared
        let availableConfigurations = modeManager.enabledConfigurations

        guard index < availableConfigurations.count else { return }

        let selectedConfig = availableConfigurations[index]
        modeManager.setActiveConfiguration(selectedConfig)
    }

    deinit {
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }
        if let settingsChangeObserver {
            NotificationCenter.default.removeObserver(settingsChangeObserver)
        }

        visibilityTask?.cancel()
        MainActor.assumeIsolated {
            visibleRecorderMonitor.stop()
            resetEscapeState()
        }
    }

    private static let digitKeyCodes: [UInt16] = [
        UInt16(kVK_ANSI_1),
        UInt16(kVK_ANSI_2),
        UInt16(kVK_ANSI_3),
        UInt16(kVK_ANSI_4),
        UInt16(kVK_ANSI_5),
        UInt16(kVK_ANSI_6),
        UInt16(kVK_ANSI_7),
        UInt16(kVK_ANSI_8),
        UInt16(kVK_ANSI_9),
        UInt16(kVK_ANSI_0),
    ]
}
