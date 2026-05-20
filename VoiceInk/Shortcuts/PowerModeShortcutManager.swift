import Foundation

@MainActor
class PowerModeShortcutManager {
    private let shortcutMonitor = ShortcutMonitor()
    private let modeProvider: @MainActor () -> RecordingShortcutManager.Mode
    private let shortcutModeHandler: RecordingShortcutModeHandler
    private var shortcutChangeObserver: NSObjectProtocol?

    init(
        modeProvider: @escaping @MainActor () -> RecordingShortcutManager.Mode,
        shortcutModeHandler: RecordingShortcutModeHandler
    ) {
        self.modeProvider = modeProvider
        self.shortcutModeHandler = shortcutModeHandler

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
            onKeyDown: { [weak self] action, eventTime in
                Task { @MainActor in
                    guard let self,
                          let powerModeId = self.powerModeId(for: action) else {
                        return
                    }

                    await self.shortcutModeHandler.handleKeyDown(
                        action: action,
                        eventTime: eventTime,
                        mode: self.modeProvider(),
                        powerModeId: powerModeId
                    )
                }
            },
            onKeyUp: { [weak self] action, eventTime in
                Task { @MainActor in
                    guard let self,
                          let powerModeId = self.powerModeId(for: action) else {
                        return
                    }

                    await self.shortcutModeHandler.handleKeyUp(
                        action: action,
                        eventTime: eventTime,
                        mode: self.modeProvider(),
                        powerModeId: powerModeId
                    )
                }
            },
            onShortcutInterrupted: { [weak self] action, _ in
                Task { @MainActor in
                    guard let self, case .powerMode = action else { return }
                    await self.shortcutModeHandler.handleInterruption(action: action)
                }
            }
        )
    }

    private func powerModeId(for action: ShortcutAction) -> UUID? {
        guard case .powerMode(let powerModeId) = action,
              let config = PowerModeManager.shared.getConfiguration(with: powerModeId),
              config.isEnabled,
              ShortcutStore.shortcut(for: .powerMode(config.id)) != nil else {
            return nil
        }

        return powerModeId
    }
}
