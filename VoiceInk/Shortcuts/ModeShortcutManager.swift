import Foundation

@MainActor
class ModeShortcutManager {
    private let shortcutMonitor = ShortcutMonitor(ownerLabel: "Mode")
    private let modeProvider: @MainActor () -> RecordingShortcutManager.Mode
    private let shortcutModeHandler: RecordingShortcutModeHandler
    private var shortcutChangeObserver: NSObjectProtocol?

    init(
        modeProvider: @escaping @MainActor () -> RecordingShortcutManager.Mode,
        shortcutModeHandler: RecordingShortcutModeHandler
    ) {
        self.modeProvider = modeProvider
        self.shortcutModeHandler = shortcutModeHandler

        ShortcutDiagnostics.notice("mode-manager init")
        refreshModeShortcuts(reason: "initialization")

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
                self?.refreshModeShortcuts(reason: "shortcut-store-notification.\(action.storageName)")
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
            ShortcutDiagnostics.notice("mode-manager deinit")
            shortcutMonitor.stop(reason: "mode-manager-deinit")
        }
    }

    @objc private func modeShortcutAvailabilityDidChange() {
        Task { @MainActor in
            refreshModeShortcuts(reason: "mode-availability-notification")
        }
    }

    private func refreshModeShortcuts(reason: String) {
        let enabledConfigurations = ModeManager.shared.enabledConfigurations
        var missingShortcutModeIDs: [String] = []
        let shortcuts = enabledConfigurations.reduce(into: [ShortcutAction: Shortcut]()) { result, config in
            let action = ShortcutAction.mode(config.id)
            if let shortcut = ShortcutStore.shortcut(for: action) {
                result[action] = shortcut
            } else {
                missingShortcutModeIDs.append(config.id.uuidString)
            }
        }

        let summary = shortcuts.map { "\($0.key.storageName)=\($0.value.diagnosticDescription)" }.sorted().joined(separator: " | ")
        ShortcutDiagnostics.notice(
            "mode-manager refresh begin reason=\(reason) enabledModeCount=\(enabledConfigurations.count) registeredCount=\(shortcuts.count) missingShortcutModeIDs=\(missingShortcutModeIDs.sorted().joined(separator: ",")) shortcuts={\(summary.isEmpty ? "none" : summary)}"
        )

        let didStart = shortcutMonitor.start(
            shortcuts: shortcuts,
            interruptibleActions: Set(shortcuts.keys),
            onKeyDown: { [weak self] action, eventTime in
                ShortcutDiagnostics.notice(
                    "mode-manager dispatch-received action=\(action.storageName) transition=keyDown eventUptime=\(eventTime)"
                )
                Task { @MainActor in
                    guard let self else {
                        ShortcutDiagnostics.notice(
                            "mode-manager dispatch-dropped action=\(action.storageName) transition=keyDown reason=manager-released"
                        )
                        return
                    }
                    guard let modeId = self.modeId(for: action) else {
                        ShortcutDiagnostics.notice(
                            "mode-manager dispatch-dropped action=\(action.storageName) transition=keyDown reason=mode-unavailable"
                        )
                        return
                    }

                    await self.shortcutModeHandler.handleKeyDown(
                        action: action,
                        eventTime: eventTime,
                        mode: self.modeProvider(),
                        modeId: modeId
                    )
                }
            },
            onKeyUp: { [weak self] action, eventTime in
                ShortcutDiagnostics.notice(
                    "mode-manager dispatch-received action=\(action.storageName) transition=keyUp eventUptime=\(eventTime)"
                )
                Task { @MainActor in
                    guard let self else {
                        ShortcutDiagnostics.notice(
                            "mode-manager dispatch-dropped action=\(action.storageName) transition=keyUp reason=manager-released"
                        )
                        return
                    }
                    guard case .mode(let modeId) = action else {
                        ShortcutDiagnostics.notice(
                            "mode-manager dispatch-dropped action=\(action.storageName) transition=keyUp reason=not-mode-action"
                        )
                        return
                    }

                    await self.shortcutModeHandler.handleKeyUp(
                        action: action,
                        eventTime: eventTime,
                        mode: self.modeProvider(),
                        modeId: modeId
                    )
                }
            },
            onShortcutInterrupted: { [weak self] action, _ in
                ShortcutDiagnostics.notice(
                    "mode-manager dispatch-received action=\(action.storageName) transition=interrupted"
                )
                Task { @MainActor in
                    guard let self else {
                        ShortcutDiagnostics.notice(
                            "mode-manager dispatch-dropped action=\(action.storageName) transition=interrupted reason=manager-released"
                        )
                        return
                    }
                    guard case .mode = action else {
                        ShortcutDiagnostics.notice(
                            "mode-manager dispatch-dropped action=\(action.storageName) transition=interrupted reason=not-mode-action"
                        )
                        return
                    }
                    await self.shortcutModeHandler.handleInterruption(action: action)
                }
            }
        )
        ShortcutDiagnostics.notice("mode-manager refresh end reason=\(reason) monitorStarted=\(didStart)")
    }

    private func modeId(for action: ShortcutAction) -> UUID? {
        guard case .mode(let modeId) = action else {
            ShortcutDiagnostics.notice("mode-manager resolve action=\(action.storageName) result=not-mode-action")
            return nil
        }
        guard let config = ModeManager.shared.getConfiguration(with: modeId) else {
            ShortcutDiagnostics.notice("mode-manager resolve action=\(action.storageName) result=configuration-missing")
            return nil
        }
        guard config.isEnabled else {
            ShortcutDiagnostics.notice("mode-manager resolve action=\(action.storageName) result=configuration-disabled")
            return nil
        }
        guard ShortcutStore.shortcut(for: .mode(config.id)) != nil else {
            ShortcutDiagnostics.notice("mode-manager resolve action=\(action.storageName) result=shortcut-missing")
            return nil
        }

        ShortcutDiagnostics.notice("mode-manager resolve action=\(action.storageName) result=available")
        return modeId
    }
}
