import Foundation
import KeyboardShortcuts

@MainActor
class PowerModeShortcutManager {
    private weak var whisperState: WhisperState?
    private var registeredPowerModeIds: Set<UUID> = []

    init(whisperState: WhisperState) {
        self.whisperState = whisperState
        
        setupPowerModeHotkeys()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerModeConfigurationsDidChange),
            name: NSNotification.Name("PowerModeConfigurationsDidChange"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func powerModeConfigurationsDidChange() {
        Task { @MainActor in
            setupPowerModeHotkeys()
        }
    }

    private func setupPowerModeHotkeys() {
        let powerModesWithShortcuts = Set(PowerModeManager.shared.configurations
            .filter { $0.hotkeyShortcut != nil }
            .map { $0.id })

        // Remove shortcuts for deleted or updated configs
        let idsToRemove = registeredPowerModeIds.subtracting(powerModesWithShortcuts)
        idsToRemove.forEach { id in
            KeyboardShortcuts.setShortcut(nil, for: .powerMode(id: id))
            registeredPowerModeIds.remove(id)
        }

        // Add new shortcuts
        PowerModeManager.shared.configurations.forEach { config in
            guard config.hotkeyShortcut != nil else { return }
            guard !registeredPowerModeIds.contains(config.id) else { return }

            KeyboardShortcuts.onKeyUp(for: .powerMode(id: config.id)) { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.handlePowerModeHotkey(powerModeId: config.id)
                }
            }

            registeredPowerModeIds.insert(config.id)
        }
    }

    private func handlePowerModeHotkey(powerModeId: UUID) async {
        guard let whisperState = whisperState,
              canProcessHotkeyAction(whisperState: whisperState) else { return }

        guard let config = PowerModeManager.shared.getConfiguration(with: powerModeId),
              config.hotkeyShortcut != nil else {
            return
        }

        await whisperState.toggleMiniRecorder(powerModeId: powerModeId)
    }
    
    private func canProcessHotkeyAction(whisperState: WhisperState) -> Bool {
        whisperState.recordingState != .transcribing && 
        whisperState.recordingState != .enhancing && 
        whisperState.recordingState != .busy
    }
}

// MARK: - PowerMode Keyboard Shortcut Names
extension KeyboardShortcuts.Name {
    static func powerMode(id: UUID) -> Self {
        Self("powerMode_\(id.uuidString)")
    }
}
