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
    private var modeAvailabilityObserver: NSObjectProtocol?
    private var recordingStateCancellable: AnyCancellable?
    private var observedSendKey: FinishAndSendKey
    private let visibleRecorderMonitor: ShortcutMonitor

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

    init(
        recorderUIManager: RecorderUIManager,
        heldRecordingShortcut: @escaping @Sendable () -> Shortcut? = { nil }
    ) {
        self.recorderUIManager = recorderUIManager
        self.visibleRecorderMonitor = ShortcutMonitor(owner: "recorder-panel", heldRecordingShortcut: heldRecordingShortcut)
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
                self.refreshVisibleShortcuts(reason: "send-key-changed")
            }
        }
        // Enabling or disabling modes changes which cancellation chords are reserved.
        modeAvailabilityObserver = NotificationCenter.default.addObserver(
            forName: .modeShortcutAvailabilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshVisibleShortcuts(reason: "mode-availability") }
        }
        setupVisibilityObserver()
        recordingStateCancellable = recorderUIManager.recordingStatePublisher?.sink { [weak self] state in
            Task { @MainActor in self?.refreshVisibleShortcuts(reason: "recording-state.\(state)") }
        }
    }

    private func setupShortcutChangeObserver() {
        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let action = notification.object as? ShortcutAction else {
                return
            }

            // Any shortcut can reserve a cancellation chord.
            Task { @MainActor in
                if action == .cancelRecorder {
                    self?.resetEscapeState()
                }
                self?.refreshVisibleShortcuts(reason: "store-change.\(action.storageName)")
            }
        }
    }

    private func setupVisibilityObserver() {
        let visibilityChanges = recorderUIManager.$isRecorderPanelVisible.values
        visibilityTask = Task { @MainActor [weak self] in
            for await isVisible in visibilityChanges {
                guard let self else { return }
                if isVisible {
                    self.refreshVisibleShortcuts(reason: "panel-visible")
                } else {
                    self.visibleRecorderMonitor.stop(reason: "panel-hidden")
                    self.resetEscapeState()
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

    private func refreshVisibleShortcuts(reason: String) {
        guard recorderUIManager.isRecorderPanelVisible else {
            visibleRecorderMonitor.stop(reason: "panel-hidden")
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

        // Exact assignments take priority over cancellation with recording modifiers.
        let reservedActions = [ShortcutAction.primaryRecording, .secondaryRecording]
            + ShortcutAction.globalUtilityActions
            + ModeManager.shared.enabledConfigurations.map { ShortcutAction.mode($0.id) }
        let reservedShortcuts = Array(ShortcutStore.shortcuts(for: reservedActions).values)
            + shortcuts.filter { $0.key != .cancelRecorder && $0.key != .recorderPanelEscape }.map(\.value)

        visibleRecorderMonitor.start(
            shortcuts: shortcuts,
            reservedShortcuts: reservedShortcuts,
            onShortcutDown: { [weak self] action, _ in
                await self?.handleRecorderPanelShortcut(action)
            },
            onShortcutUp: { _, _ in },
            reason: reason
        )
    }

    private func handleRecorderPanelShortcut(_ action: ShortcutAction) async {
        guard recorderUIManager.isRecorderPanelVisible else {
            ShortcutDiagnostics.notice("panel action=\(action.storageName) result=ignored reason=panel-hidden")
            return
        }

        switch action {
        case .cancelRecorder:
            guard ShortcutStore.shortcut(for: .cancelRecorder) != nil else {
                ShortcutDiagnostics.notice("panel action=cancelRecorder result=ignored reason=shortcut-cleared")
                return
            }
            ShortcutDiagnostics.notice("panel action=cancelRecorder result=cancel-requested")
            await recorderUIManager.cancelRecording()
        case .recorderPanelEscape:
            await handleEscapeShortcut()
        case .recorderPanelReturn:
            if FinishAndSendSettings.selectedKey.isEnabled {
                ShortcutDiagnostics.notice("panel action=recorderPanelReturn result=finish-and-send-requested")
                await recorderUIManager.finishRecordingAndSend()
            } else {
                ShortcutDiagnostics.notice("panel action=recorderPanelReturn result=ignored reason=send-key-disabled")
            }
        case .recorderPanelMode(let index):
            handleModeSelectionShortcut(index: index)
        default:
            break
        }
    }

    private func handleEscapeShortcut() async {
        guard ShortcutStore.shortcut(for: .cancelRecorder) == nil else {
            ShortcutDiagnostics.notice("panel action=recorderPanelEscape result=ignored reason=custom-cancel-shortcut")
            return
        }

        let now = Date()
        if let firstTime = firstEscapePressTime,
            now.timeIntervalSince(firstTime) <= escapeDoublePressThreshold
        {
            ShortcutDiagnostics.notice("panel action=recorderPanelEscape result=cancel-confirmed")
            resetEscapeState()
            await recorderUIManager.cancelRecording()
            return
        }

        ShortcutDiagnostics.notice("panel action=recorderPanelEscape result=waiting-confirmation")
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
        guard canUseModeShortcuts else {
            ShortcutDiagnostics.notice("panel action=recorderPanelMode_\(index) result=ignored reason=no-enabled-modes")
            return
        }

        let modeManager = ModeManager.shared
        let availableConfigurations = modeManager.enabledConfigurations

        guard index < availableConfigurations.count else {
            ShortcutDiagnostics.notice("panel action=recorderPanelMode_\(index) result=ignored reason=mode-unavailable")
            return
        }

        let selectedConfig = availableConfigurations[index]
        ShortcutDiagnostics.notice("panel action=recorderPanelMode_\(index) result=mode-selected modeID=\(selectedConfig.id)")
        modeManager.setActiveConfiguration(selectedConfig)
    }

    isolated deinit {
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }
        if let settingsChangeObserver {
            NotificationCenter.default.removeObserver(settingsChangeObserver)
        }
        if let modeAvailabilityObserver {
            NotificationCenter.default.removeObserver(modeAvailabilityObserver)
        }

        visibilityTask?.cancel()
        recordingStateCancellable?.cancel()
        visibleRecorderMonitor.stop(reason: "deinit")
        resetEscapeState()
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
