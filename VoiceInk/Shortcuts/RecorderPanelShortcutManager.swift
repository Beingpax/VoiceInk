import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class RecorderPanelShortcutManager: ObservableObject {
    private var recorderUIManager: RecorderUIManager
    private var visibilityTask: Task<Void, Never>?
    private var shortcutChangeObserver: NSObjectProtocol?
    private let visibleRecorderMonitor = ShortcutMonitor(ownerLabel: "RecorderPanel")

    // Double-tap Escape handling
    private var firstEscapePressTime: Date? = nil
    private let escapeDoublePressThreshold: TimeInterval = 1.5
    private var escapeTimeoutTask: Task<Void, Never>?

    init(recorderUIManager: RecorderUIManager) {
        self.recorderUIManager = recorderUIManager
        ShortcutDiagnostics.notice(
            "panel-shortcut-manager init recorderVisible=\(recorderUIManager.isRecorderPanelVisible)"
        )
        setupShortcutChangeObserver()
        setupVisibilityObserver()
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
                self?.refreshVisibleShortcuts(reason: "cancel-shortcut-changed")
            }
        }
    }

    private func setupVisibilityObserver() {
        visibilityTask = Task { @MainActor in
            for await isVisible in recorderUIManager.$isRecorderPanelVisible.values {
                ShortcutDiagnostics.notice("panel-shortcut-manager visibility-changed visible=\(isVisible)")
                if isVisible {
                    refreshVisibleShortcuts(reason: "recorder-became-visible")
                } else {
                    visibleRecorderMonitor.stop(reason: "recorder-became-hidden")
                    resetEscapeState()
                }
            }
        }
    }

    private var canUseModeShortcuts: Bool {
        !ModeManager.shared.enabledConfigurations.isEmpty
    }

    private func resetEscapeState() {
        if firstEscapePressTime != nil || escapeTimeoutTask != nil {
            ShortcutDiagnostics.notice("panel-shortcut-manager escape-state reset")
        }
        firstEscapePressTime = nil
        escapeTimeoutTask?.cancel()
        escapeTimeoutTask = nil
    }

    private func refreshVisibleShortcuts(reason: String) {
        guard recorderUIManager.isRecorderPanelVisible else {
            ShortcutDiagnostics.notice(
                "panel-shortcut-manager refresh reason=\(reason) result=stopped-recorder-hidden"
            )
            visibleRecorderMonitor.stop(reason: "refresh-hidden.\(reason)")
            resetEscapeState()
            return
        }

        var shortcuts = ShortcutStore.shortcuts(for: ShortcutAction.recorderPanelStoredActions)

        if ShortcutStore.shortcut(for: .cancelRecorder) == nil {
            shortcuts[.recorderPanelEscape] = .key(keyCode: UInt16(kVK_Escape), modifierFlags: [])
        }

        if canUseModeShortcuts {
            for (index, keyCode) in Self.digitKeyCodes.enumerated() {
                shortcuts[.recorderPanelMode(index)] = .key(
                    keyCode: keyCode,
                    modifierFlags: [.option]
                )
            }
        }

        let summary = shortcuts.map { "\($0.key.storageName)=\($0.value.diagnosticDescription)" }.sorted().joined(separator: " | ")
        ShortcutDiagnostics.notice(
            "panel-shortcut-manager refresh begin reason=\(reason) storedCancelConfigured=\(ShortcutStore.shortcut(for: .cancelRecorder) != nil) canUseModeShortcuts=\(canUseModeShortcuts) shortcutCount=\(shortcuts.count) shortcuts={\(summary.isEmpty ? "none" : summary)}"
        )
        let didStart = visibleRecorderMonitor.start(
            shortcuts: shortcuts,
            onKeyDown: { [weak self] action, _ in
                ShortcutDiagnostics.notice(
                    "panel-shortcut-manager dispatch-received action=\(action.storageName) transition=keyDown"
                )
                Task { @MainActor in
                    await self?.handleRecorderPanelShortcut(action)
                }
            },
            onKeyUp: { _, _ in }
        )
        ShortcutDiagnostics.notice(
            "panel-shortcut-manager refresh end reason=\(reason) monitorStarted=\(didStart)"
        )
    }

    private func handleRecorderPanelShortcut(_ action: ShortcutAction) async {
        guard recorderUIManager.isRecorderPanelVisible else {
            ShortcutDiagnostics.notice(
                "panel-shortcut-manager handle action=\(action.storageName) result=rejected reason=recorder-hidden"
            )
            return
        }

        ShortcutDiagnostics.notice("panel-shortcut-manager handle action=\(action.storageName) begin")

        switch action {
        case .cancelRecorder:
            guard ShortcutStore.shortcut(for: .cancelRecorder) != nil else {
                ShortcutDiagnostics.notice(
                    "panel-shortcut-manager handle action=\(action.storageName) result=rejected reason=stored-cancel-missing"
                )
                return
            }
            ShortcutDiagnostics.notice("panel-shortcut-manager handle action=\(action.storageName) result=cancel-recording")
            await recorderUIManager.cancelRecording()
        case .recorderPanelEscape:
            await handleEscapeShortcut()
        case .recorderPanelMode(let index):
            handleModeSelectionShortcut(index: index)
        default:
            ShortcutDiagnostics.notice(
                "panel-shortcut-manager handle action=\(action.storageName) result=no-handler"
            )
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
            ShortcutDiagnostics.notice("panel-shortcut-manager escape result=cancel-recording secondPress=true")
            await recorderUIManager.cancelRecording()
            return
        }

        firstEscapePressTime = now
        ShortcutDiagnostics.notice("panel-shortcut-manager escape result=waiting-for-second-press")
        NotificationManager.shared.showNotification(
            title: String(localized: "Press Esc again to cancel"),
            type: .info,
            duration: escapeDoublePressThreshold
        )
        escapeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.escapeDoublePressThreshold ?? 1.5) * 1_000_000_000))
            await MainActor.run {
                self?.firstEscapePressTime = nil
                ShortcutDiagnostics.notice("panel-shortcut-manager escape result=second-press-timeout")
            }
        }
    }

    private func handleModeSelectionShortcut(index: Int) {
        guard canUseModeShortcuts else {
            ShortcutDiagnostics.notice(
                "panel-shortcut-manager mode-select index=\(index) result=rejected reason=no-enabled-modes"
            )
            return
        }

        let modeManager = ModeManager.shared
        let availableConfigurations = modeManager.enabledConfigurations

        guard index < availableConfigurations.count else {
            ShortcutDiagnostics.notice(
                "panel-shortcut-manager mode-select index=\(index) result=rejected reason=index-out-of-range availableCount=\(availableConfigurations.count)"
            )
            return
        }

        let selectedConfig = availableConfigurations[index]
        ShortcutDiagnostics.notice(
            "panel-shortcut-manager mode-select index=\(index) result=selected modeId=\(selectedConfig.id.uuidString)"
        )
        modeManager.setActiveConfiguration(selectedConfig)
    }

    deinit {
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }

        visibilityTask?.cancel()
        MainActor.assumeIsolated {
            ShortcutDiagnostics.notice("panel-shortcut-manager deinit")
            visibleRecorderMonitor.stop(reason: "panel-shortcut-manager-deinit")
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
