import Foundation
import KeyboardShortcuts
import Carbon
import AppKit

extension KeyboardShortcuts.Name {
    static let toggleMiniRecorder = Self("toggleMiniRecorder")
    static let toggleMiniRecorder2 = Self("toggleMiniRecorder2")
    static let toggleScratchpad = Self("toggleScratchpad")
}

@MainActor
class HotkeyManager: ObservableObject {
    @Published var selectedHotkey1: HotkeyOption {
        didSet {
            UserDefaults.standard.set(selectedHotkey1.rawValue, forKey: "selectedHotkey1")
            setupHotkeyMonitoring()
        }
    }
    @Published var selectedHotkey2: HotkeyOption {
        didSet {
            UserDefaults.standard.set(selectedHotkey2.rawValue, forKey: "selectedHotkey2")
            setupHotkeyMonitoring()
        }
    }
    @Published var selectedScratchpadHotkey: HotkeyOption {
        didSet {
            UserDefaults.standard.set(selectedScratchpadHotkey.rawValue, forKey: "selectedScratchpadHotkey")
            setupHotkeyMonitoring()
        }
    }
    
    private var whisperState: WhisperState
    private var miniRecorderShortcutManager: MiniRecorderShortcutManager
    
    // NSEvent monitoring for modifier keys
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    
    // Key state tracking
    private var currentKeyState = false
    private var keyPressStartTime: Date?
    private let briefPressThreshold = 1.0 // 1 second threshold for brief press
    private var isHandsFreeMode = false
    
    // Debounce for Fn key
    private var fnDebounceTask: Task<Void, Never>?
    private var pendingFnKeyState: Bool? = nil
    
    // Keyboard shortcut state tracking
    private var shortcutKeyPressStartTime: Date?
    private var isShortcutHandsFreeMode = false
    private var shortcutCurrentKeyState = false
    private var lastShortcutTriggerTime: Date?
    private let shortcutCooldownInterval: TimeInterval = 0.5
    
    enum HotkeyType {
        case regular
        case scratchpad
    }
    
    enum HotkeyOption: String, CaseIterable {
        case none = "none"
        case rightOption = "rightOption"
        case leftOption = "leftOption"
        case leftControl = "leftControl" 
        case rightControl = "rightControl"
        case fn = "fn"
        case rightCommand = "rightCommand"
        case rightShift = "rightShift"
        case custom = "custom"
        
        var displayName: String {
            switch self {
            case .none: return "None"
            case .rightOption: return "Right Option (⌥)"
            case .leftOption: return "Left Option (⌥)"
            case .leftControl: return "Left Control (⌃)"
            case .rightControl: return "Right Control (⌃)"
            case .fn: return "Fn"
            case .rightCommand: return "Right Command (⌘)"
            case .rightShift: return "Right Shift (⇧)"
            case .custom: return "Custom"
            }
        }
        
        var keyCode: CGKeyCode? {
            switch self {
            case .rightOption: return 0x3D
            case .leftOption: return 0x3A
            case .leftControl: return 0x3B
            case .rightControl: return 0x3E
            case .fn: return 0x3F
            case .rightCommand: return 0x36
            case .rightShift: return 0x3C
            case .custom, .none: return nil
            }
        }
        
        var isModifierKey: Bool {
            return self != .custom && self != .none
        }
    }
    
    init(whisperState: WhisperState) {
        // One-time migration from legacy single-hotkey settings
        if UserDefaults.standard.object(forKey: "didMigrateHotkeys_v2") == nil {
            // If legacy push-to-talk modifier key was enabled, carry it over
            if UserDefaults.standard.bool(forKey: "isPushToTalkEnabled"),
               let legacyRaw = UserDefaults.standard.string(forKey: "pushToTalkKey"),
               let legacyKey = HotkeyOption(rawValue: legacyRaw) {
                UserDefaults.standard.set(legacyKey.rawValue, forKey: "selectedHotkey1")
            }
            // If a custom shortcut existed, mark hotkey-1 as custom (shortcut itself already persisted)
            if KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) != nil {
                UserDefaults.standard.set(HotkeyOption.custom.rawValue, forKey: "selectedHotkey1")
            }
            // Leave second hotkey as .none
            UserDefaults.standard.set(true, forKey: "didMigrateHotkeys_v2")
        }
        // ---- normal initialisation ----
        self.selectedHotkey1 = HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey1") ?? "") ?? .rightCommand
        self.selectedHotkey2 = HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey2") ?? "") ?? .none
        self.selectedScratchpadHotkey = HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedScratchpadHotkey") ?? "") ?? .none
        self.whisperState = whisperState
        self.miniRecorderShortcutManager = MiniRecorderShortcutManager(whisperState: whisperState)
    }
    
    func startHotkeyMonitoring() {
        setupHotkeyMonitoring()
    }
    
    private func setupHotkeyMonitoring() {
        removeAllMonitoring()
        
        setupModifierKeyMonitoring()
        setupCustomShortcutMonitoring()
    }
    
    private func setupModifierKeyMonitoring() {
        // Only set up if at least one hotkey is a modifier key
        guard (selectedHotkey1.isModifierKey && selectedHotkey1 != .none) || 
              (selectedHotkey2.isModifierKey && selectedHotkey2 != .none) || 
              (selectedScratchpadHotkey.isModifierKey && selectedScratchpadHotkey != .none) else { return }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleModifierKeyEvent(event)
            }
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            Task { @MainActor in
                await self.handleModifierKeyEvent(event)
            }
            return event
        }
    }
    
    private func setupCustomShortcutMonitoring() {
        // Hotkey 1
        if selectedHotkey1 == .custom {
            KeyboardShortcuts.onKeyDown(for: .toggleMiniRecorder) { [weak self] in
                Task { @MainActor in await self?.handleCustomShortcutKeyDown() }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleMiniRecorder) { [weak self] in
                Task { @MainActor in await self?.handleCustomShortcutKeyUp() }
            }
        }
        // Hotkey 2
        if selectedHotkey2 == .custom {
            KeyboardShortcuts.onKeyDown(for: .toggleMiniRecorder2) { [weak self] in
                Task { @MainActor in await self?.handleCustomShortcutKeyDown() }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleMiniRecorder2) { [weak self] in
                Task { @MainActor in await self?.handleCustomShortcutKeyUp() }
            }
        }
        
        // Scratchpad shortcut
        if selectedScratchpadHotkey == .custom {
            KeyboardShortcuts.onKeyUp(for: .toggleScratchpad) { [weak self] in
                Task { @MainActor in
                    await self?.handleScratchpadShortcutTriggered()
                }
            }
        }
    }
    
    private func handleScratchpadShortcutTriggered() async {
        // Add same blocking checks as regular hotkeys
        if whisperState.isRecording || whisperState.isTranscribing || whisperState.isProcessing {
            return
        }
        
        await whisperState.startScratchpadRecording()
    }
    
    private func removeAllMonitoring() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        
        resetKeyStates()
    }
    
    private func resetKeyStates() {
        currentKeyState = false
        keyPressStartTime = nil
        isHandsFreeMode = false
        shortcutCurrentKeyState = false
        shortcutKeyPressStartTime = nil
        isShortcutHandsFreeMode = false
    }
    
    private func handleModifierKeyEvent(_ event: NSEvent) async {
        let keycode = event.keyCode
        let flags = event.modifierFlags
        
        // Determine which hotkey (if any) is being triggered
        let activeHotkey: (option: HotkeyOption, type: HotkeyType)?
        if selectedHotkey1.isModifierKey && selectedHotkey1.keyCode == keycode {
            activeHotkey = (selectedHotkey1, .regular)
        } else if selectedHotkey2.isModifierKey && selectedHotkey2.keyCode == keycode {
            activeHotkey = (selectedHotkey2, .regular)
        } else if selectedScratchpadHotkey.isModifierKey && selectedScratchpadHotkey.keyCode == keycode {
            activeHotkey = (selectedScratchpadHotkey, .scratchpad)
        } else {
            activeHotkey = nil
        }
        
        guard let hotkey = activeHotkey else { return }
        
        var isKeyPressed = false
        
        switch hotkey.option {
        case .rightOption, .leftOption:
            isKeyPressed = flags.contains(.option)
        case .leftControl, .rightControl:
            isKeyPressed = flags.contains(.control)
        case .fn:
            isKeyPressed = flags.contains(.function)
            // Debounce Fn key
            pendingFnKeyState = isKeyPressed
            fnDebounceTask?.cancel()
            fnDebounceTask = Task { [pendingState = isKeyPressed] in
                try? await Task.sleep(nanoseconds: 75_000_000) // 75ms
                if pendingFnKeyState == pendingState {
                    await MainActor.run {
                        self.processKeyPress(isKeyPressed: pendingState, type: hotkey.type)
                    }
                }
            }
            return
        case .rightCommand:
            isKeyPressed = flags.contains(.command)
        case .rightShift:
            isKeyPressed = flags.contains(.shift)
        case .custom, .none:
            return // Should not reach here
        }
        
        processKeyPress(isKeyPressed: isKeyPressed, type: hotkey.type)
    }
    
    private func processKeyPress(isKeyPressed: Bool, type: HotkeyType = .regular) {
        guard isKeyPressed != currentKeyState else { return }
        currentKeyState = isKeyPressed
        
        if isKeyPressed {
            keyPressStartTime = Date()
            
            if isHandsFreeMode {
                isHandsFreeMode = false
                Task { @MainActor in
                    guard !whisperState.isTranscribing && !whisperState.isProcessing else { return }
                    if type == .scratchpad {
                        await whisperState.startScratchpadRecording()
                    } else {
                        await whisperState.handleToggleMiniRecorder()
                    }
                }
                return
            }
            
            if !whisperState.isMiniRecorderVisible {
                Task { @MainActor in
                    guard !whisperState.isTranscribing && !whisperState.isProcessing else { return }
                    if type == .scratchpad {
                        await whisperState.startScratchpadRecording()
                    } else {
                        await whisperState.handleToggleMiniRecorder()
                    }
                }
            }
        } else {
            let now = Date()
            
            if let startTime = keyPressStartTime {
                let pressDuration = now.timeIntervalSince(startTime)
                
                if pressDuration < briefPressThreshold {
                    isHandsFreeMode = true
                } else {
                    Task { @MainActor in
                        guard !whisperState.isTranscribing && !whisperState.isProcessing else { return }
                        if type == .scratchpad {
                            await whisperState.startScratchpadRecording()
                        } else {
                            await whisperState.handleToggleMiniRecorder()
                        }
                    }
                }
            }
            
            keyPressStartTime = nil
        }
    }
    
    private func handleCustomShortcutKeyDown() async {
        if let lastTrigger = lastShortcutTriggerTime,
           Date().timeIntervalSince(lastTrigger) < shortcutCooldownInterval {
            return
        }
        
        guard !shortcutCurrentKeyState else { return }
        shortcutCurrentKeyState = true
        lastShortcutTriggerTime = Date()
        shortcutKeyPressStartTime = Date()
        
        if isShortcutHandsFreeMode {
            isShortcutHandsFreeMode = false
            guard !whisperState.isTranscribing && !whisperState.isProcessing else { return }
            await whisperState.handleToggleMiniRecorder()
            return
        }
        
        if !whisperState.isMiniRecorderVisible {
            guard !whisperState.isTranscribing && !whisperState.isProcessing else { return }
            await whisperState.handleToggleMiniRecorder()
        }
    }
    
    private func handleCustomShortcutKeyUp() async {
        guard shortcutCurrentKeyState else { return }
        shortcutCurrentKeyState = false
        
        let now = Date()
        
        if let startTime = shortcutKeyPressStartTime {
            let pressDuration = now.timeIntervalSince(startTime)
            
            if pressDuration < briefPressThreshold {
                isShortcutHandsFreeMode = true
            } else {
                guard !whisperState.isTranscribing && !whisperState.isProcessing else { return }
                await whisperState.handleToggleMiniRecorder()
            }
        }
        
        shortcutKeyPressStartTime = nil
    }
    
    // Computed property for backward compatibility with UI
    var isShortcutConfigured: Bool {
        let isHotkey1Configured = (selectedHotkey1 == .custom) ? (KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) != nil) : true
        let isHotkey2Configured = (selectedHotkey2 == .custom) ? (KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder2) != nil) : true
        return isHotkey1Configured && isHotkey2Configured
    }
    
    func updateShortcutStatus() {
        // Called when a custom shortcut changes
        if selectedHotkey1 == .custom || selectedHotkey2 == .custom {
            setupHotkeyMonitoring()
        }
    }
    
    deinit {
        Task { @MainActor in
            removeAllMonitoring()
        }
    }
}


