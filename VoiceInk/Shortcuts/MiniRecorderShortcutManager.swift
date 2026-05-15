import Foundation
import AppKit
import Carbon.HIToolbox

@MainActor
class MiniRecorderShortcutManager: ObservableObject {
    private var engine: VoiceInkEngine
    private var recorderUIManager: RecorderUIManager
    private var visibilityTask: Task<Void, Never>?
    private var shortcutChangeObserver: NSObjectProtocol?
    private let visibleRecorderMonitor = ShortcutMonitor()
    
    // Double-tap Escape handling
    private var firstEscapePressTime: Date? = nil
    private let escapeDoublePressThreshold: TimeInterval = 1.5
    private var escapeTimeoutTask: Task<Void, Never>?
    
    init(engine: VoiceInkEngine, recorderUIManager: RecorderUIManager) {
        self.engine = engine
        self.recorderUIManager = recorderUIManager
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
                action == .cancelRecorder || action == .toggleEnhancement
            else {
                return
            }

            Task { @MainActor in
                self?.refreshVisibleShortcuts()
            }
        }
    }

    private func setupVisibilityObserver() {
        visibilityTask = Task { @MainActor in
            for await isVisible in recorderUIManager.$isMiniRecorderVisible.values {
                if isVisible {
                    refreshVisibleShortcuts()
                } else {
                    visibleRecorderMonitor.stop()
                    resetEscapeState()
                }
            }
        }
    }

    private var canUsePowerModeShortcuts: Bool {
        UserDefaults.standard.bool(forKey: "powerModeUIFlag") &&
            !PowerModeManager.shared.enabledConfigurations.isEmpty
    }

    private func resetEscapeState() {
        firstEscapePressTime = nil
        escapeTimeoutTask?.cancel()
        escapeTimeoutTask = nil
    }
    
    private func refreshVisibleShortcuts() {
        guard recorderUIManager.isMiniRecorderVisible else {
            visibleRecorderMonitor.stop()
            resetEscapeState()
            return
        }

        var shortcuts = ShortcutStore.shortcuts(for: ShortcutAction.miniRecorderStoredActions)

        if ShortcutStore.shortcut(for: .cancelRecorder) == nil {
            shortcuts[.miniRecorderEscape] = .key(keyCode: UInt16(kVK_Escape), modifierFlags: [])
        }

        for (index, keyCode) in Self.digitKeyCodes.enumerated() {
            shortcuts[.miniRecorderPrompt(index)] = .key(
                keyCode: keyCode,
                modifierFlags: [.command]
            )
        }

        if canUsePowerModeShortcuts {
            for (index, keyCode) in Self.digitKeyCodes.enumerated() {
                shortcuts[.miniRecorderPowerMode(index)] = .key(
                    keyCode: keyCode,
                    modifierFlags: [.option]
                )
            }
        }

        visibleRecorderMonitor.start(
            shortcuts: shortcuts,
            onKeyDown: { [weak self] action, _ in
                Task { @MainActor in
                    await self?.handleMiniRecorderShortcut(action)
                }
            },
            onKeyUp: { _, _ in }
        )
    }

    private func handleMiniRecorderShortcut(_ action: ShortcutAction) async {
        guard recorderUIManager.isMiniRecorderVisible else { return }

        switch action {
        case .cancelRecorder:
            guard ShortcutStore.shortcut(for: .cancelRecorder) != nil else { return }
            await recorderUIManager.cancelRecording()
        case .toggleEnhancement:
            guard let enhancementService = engine.getEnhancementService() else { return }
            enhancementService.isEnhancementEnabled.toggle()
        case .miniRecorderEscape:
            await handleEscapeShortcut()
        case .miniRecorderPrompt(let index):
            handlePromptShortcut(index: index)
        case .miniRecorderPowerMode(let index):
            await handlePowerModeSelectionShortcut(index: index)
        default:
            break
        }
    }

    private func handleEscapeShortcut() async {
        guard ShortcutStore.shortcut(for: .cancelRecorder) == nil else { return }

        let now = Date()
        if let firstTime = firstEscapePressTime,
           now.timeIntervalSince(firstTime) <= escapeDoublePressThreshold {
            resetEscapeState()
            await recorderUIManager.cancelRecording()
            return
        }

        firstEscapePressTime = now
        SoundManager.shared.playEscSound()
        NotificationManager.shared.showNotification(
            title: "Press ESC again to cancel recording",
            type: .info,
            duration: escapeDoublePressThreshold
        )
        escapeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.escapeDoublePressThreshold ?? 1.5) * 1_000_000_000))
            await MainActor.run {
                self?.firstEscapePressTime = nil
            }
        }
    }

    private func handlePromptShortcut(index: Int) {
        guard
            let enhancementService = engine.getEnhancementService(),
            index < enhancementService.allPrompts.count
        else {
            return
        }

        if !enhancementService.isEnhancementEnabled {
            enhancementService.isEnhancementEnabled = true
        }

        enhancementService.setActivePrompt(enhancementService.allPrompts[index])
    }

    private func handlePowerModeSelectionShortcut(index: Int) async {
        guard canUsePowerModeShortcuts else { return }

        let powerModeManager = PowerModeManager.shared
        let availableConfigurations = powerModeManager.enabledConfigurations

        guard index < availableConfigurations.count else { return }

        let selectedConfig = availableConfigurations[index]
        powerModeManager.setActiveConfiguration(selectedConfig)
        await PowerModeSessionManager.shared.beginSession(with: selectedConfig)
    }

    deinit {
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
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
        UInt16(kVK_ANSI_0)
    ]
}
