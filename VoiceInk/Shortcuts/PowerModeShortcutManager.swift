import Foundation

@MainActor
class PowerModeShortcutManager {
    private weak var engine: VoiceInkEngine?
    private let shortcutMonitor = ShortcutMonitor()
    private var shortcutChangeObserver: NSObjectProtocol?
    private var interruptedPowerModeActions = Set<ShortcutAction>()

    init(engine: VoiceInkEngine) {
        self.engine = engine

        refreshPowerModeShortcuts()

        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let action = notification.object as? ShortcutAction,
                case .powerMode = action
            else {
                return
            }

            Task { @MainActor in
                self?.refreshPowerModeShortcuts()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerModeShortcutAvailabilityDidChange),
            name: .powerModeShortcutAvailabilityDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }
        MainActor.assumeIsolated {
            shortcutMonitor.stop()
        }
    }

    @objc private func powerModeShortcutAvailabilityDidChange() {
        Task { @MainActor in
            refreshPowerModeShortcuts()
        }
    }

    private func refreshPowerModeShortcuts() {
        guard UserDefaults.standard.bool(forKey: "powerModeUIFlag") else {
            shortcutMonitor.stop()
            return
        }

        let shortcuts = PowerModeManager.shared.enabledConfigurations.reduce(into: [ShortcutAction: Shortcut]()) { result, config in
            let action = ShortcutAction.powerMode(config.id)
            if let shortcut = ShortcutStore.shortcut(for: action) {
                result[action] = shortcut
            }
        }

        shortcutMonitor.start(
            shortcuts: shortcuts,
            interruptibleActions: Set(shortcuts.keys),
            onKeyDown: { _, _ in },
            onKeyUp: { [weak self] action, _ in
                Task { @MainActor in
                    guard case .powerMode(let powerModeId) = action else { return }
                    await self?.handlePowerModeShortcut(powerModeId: powerModeId)
                }
            },
            onShortcutInterrupted: { [weak self] action, _ in
                Task { @MainActor in
                    self?.handlePowerModeShortcutInterruption(action)
                }
            }
        )
    }

    private func handlePowerModeShortcut(powerModeId: UUID) async {
        guard let engine = engine,
              canHandleShortcutAction(engine: engine) else { return }

        guard let config = PowerModeManager.shared.getConfiguration(with: powerModeId),
              config.isEnabled,
              ShortcutStore.shortcut(for: .powerMode(config.id)) != nil else {
            return
        }

        let action = ShortcutAction.powerMode(powerModeId)
        if interruptedPowerModeActions.remove(action) != nil,
           canCurrentShortcutPressCancelAccidentalStart(engine: engine) {
            return
        }

        await engine.recorderUIManager?.toggleMiniRecorder(powerModeId: powerModeId)
    }

    private func handlePowerModeShortcutInterruption(_ action: ShortcutAction) {
        guard case .powerMode = action,
              let engine,
              canCurrentShortcutPressCancelAccidentalStart(engine: engine) else {
            return
        }

        interruptedPowerModeActions.insert(action)
    }

    private func canHandleShortcutAction(engine: VoiceInkEngine) -> Bool {
        engine.recordingState != .transcribing &&
        engine.recordingState != .enhancing &&
        engine.recordingState != .busy
    }

    private func canCurrentShortcutPressCancelAccidentalStart(engine: VoiceInkEngine) -> Bool {
        engine.recorderUIManager?.isMiniRecorderVisible != true && engine.recordingState == .idle
    }
}
