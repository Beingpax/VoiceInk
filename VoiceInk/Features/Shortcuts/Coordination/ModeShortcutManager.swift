import Foundation

@MainActor
class ModeShortcutManager {
    private let shortcutMonitor = ShortcutMonitor()
    private let modeProvider: @MainActor () -> RecordingShortcutManager.Mode
    private let shortcutModeHandler: RecordingShortcutModeHandler
    private var shortcutChangeObserver: NSObjectProtocol?
    private var monitoredActions = Set<ShortcutAction>()

    init(
        modeProvider: @escaping @MainActor () -> RecordingShortcutManager.Mode,
        shortcutModeHandler: RecordingShortcutModeHandler
    ) {
        self.modeProvider = modeProvider
        self.shortcutModeHandler = shortcutModeHandler

        refreshModeShortcuts()

        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let action = notification.object as? ShortcutAction,
                case .mode = action
            else {
                return
            }

            Task { @MainActor in
                self?.refreshModeShortcuts()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modeShortcutAvailabilityDidChange),
            name: .modeShortcutAvailabilityDidChange,
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

    @objc private func modeShortcutAvailabilityDidChange() {
        Task { @MainActor in
            refreshModeShortcuts()
        }
    }

    func recordingModeDidChange() {
        shortcutMonitor.updateStandaloneModifierActions(standaloneModifierActions)
    }

    private func refreshModeShortcuts() {
        shortcutModeHandler.clearPendingModeDoubleTaps()
        let shortcuts = ModeManager.shared.enabledConfigurations.reduce(into: [ShortcutAction: Shortcut]()) {
            result, config in
            let action = ShortcutAction.mode(config.id)
            if let shortcut = ShortcutStore.shortcut(for: action) {
                result[action] = shortcut
            }
        }
        monitoredActions = Set(shortcuts.keys)

        shortcutMonitor.start(
            shortcuts: shortcuts,
            interruptibleActions: Set(shortcuts.keys),
            standaloneModifierActions: standaloneModifierActions,
            onShortcutDown: { [weak self] action, eventTime in
                Task { @MainActor in
                    guard let self,
                        let modeId = self.modeId(for: action)
                    else {
                        return
                    }

                    await self.shortcutModeHandler.handleShortcutDown(
                        action: action,
                        eventTime: eventTime,
                        mode: self.modeProvider(),
                        modeId: modeId
                    )
                }
            },
            onShortcutUp: { [weak self] action, eventTime in
                Task { @MainActor in
                    guard let self,
                        case .mode(let modeId) = action
                    else {
                        return
                    }

                    await self.shortcutModeHandler.handleShortcutUp(
                        action: action,
                        eventTime: eventTime,
                        mode: self.modeProvider(),
                        modeId: modeId
                    )
                }
            },
            onShortcutInterrupted: { [weak self] action, _ in
                Task { @MainActor in
                    guard let self, case .mode = action else { return }
                    await self.shortcutModeHandler.handleInterruption(action: action)
                }
            },
            onStandaloneModifierChord: { [weak self] action in
                MainActor.assumeIsolated {
                    self?.shortcutModeHandler.clearPendingDoubleTap(for: action)
                }
            }
        )
    }

    private var standaloneModifierActions: Set<ShortcutAction> {
        modeProvider() == .toggle || modeProvider() == .doubleTap ? monitoredActions : []
    }

    private func modeId(for action: ShortcutAction) -> UUID? {
        guard case .mode(let modeId) = action,
            let config = ModeManager.shared.getConfiguration(with: modeId),
            config.isEnabled,
            ShortcutStore.shortcut(for: .mode(config.id)) != nil
        else {
            return nil
        }

        return modeId
    }
}
