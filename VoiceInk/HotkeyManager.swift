import Foundation
import KeyboardShortcuts
import Carbon
import AppKit
import os

extension KeyboardShortcuts.Name {
    static let toggleMiniRecorder = Self("toggleMiniRecorder")
    static let toggleMiniRecorder2 = Self("toggleMiniRecorder2")
    static let pasteLastTranscription = Self("pasteLastTranscription")
    static let pasteLastEnhancement = Self("pasteLastEnhancement")
    static let retryLastTranscription = Self("retryLastTranscription")
    static let openHistoryWindow = Self("openHistoryWindow")
}

@MainActor
class HotkeyManager: ObservableObject {
    @Published var selectedHotkey1: HotkeyOption {
        didSet {
            UserDefaults.standard.set(selectedHotkey1.rawValue, forKey: "selectedHotkey1")
            if selectedHotkey1 != oldValue {
                companionModifier1 = .none
            }
            setupHotkeyMonitoring()
        }
    }
    @Published var selectedHotkey2: HotkeyOption {
        didSet {
            if selectedHotkey2 == .none {
                KeyboardShortcuts.setShortcut(nil, for: .toggleMiniRecorder2)
            }
            UserDefaults.standard.set(selectedHotkey2.rawValue, forKey: "selectedHotkey2")
            if selectedHotkey2 != oldValue {
                companionModifier2 = .none
            }
            setupHotkeyMonitoring()
        }
    }
    @Published var companionModifier1: CompanionModifier {
        didSet {
            UserDefaults.standard.set(companionModifier1.rawValue, forKey: "companionModifier1")
            resetKeyStates()
        }
    }
    @Published var companionModifier2: CompanionModifier {
        didSet {
            UserDefaults.standard.set(companionModifier2.rawValue, forKey: "companionModifier2")
            resetKeyStates()
        }
    }
    @Published var recordingMode: RecordingMode {
        didSet {
            UserDefaults.standard.set(recordingMode.rawValue, forKey: "recordingMode")
            resetKeyStates()
        }
    }
    @Published var isMiddleClickToggleEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMiddleClickToggleEnabled, forKey: "isMiddleClickToggleEnabled")
            setupHotkeyMonitoring()
        }
    }
    @Published var middleClickActivationDelay: Int {
        didSet {
            UserDefaults.standard.set(middleClickActivationDelay, forKey: "middleClickActivationDelay")
        }
    }
    
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "HotkeyManager")
    private var whisperState: WhisperState
    private var miniRecorderShortcutManager: MiniRecorderShortcutManager
    private var powerModeShortcutManager: PowerModeShortcutManager
    
    // MARK: - Helper Properties
    private var canProcessHotkeyAction: Bool {
        whisperState.recordingState != .transcribing && whisperState.recordingState != .enhancing && whisperState.recordingState != .busy
    }
    
    // NSEvent monitoring for modifier keys
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    
    // Middle-click event monitoring
    private var middleClickMonitors: [Any?] = []
    private var middleClickTask: Task<Void, Never>?
    
    // Key state tracking
    private var currentKeyState = false
    private var keyPressEventTime: TimeInterval?
    private let briefPressThreshold = 0.5
    private var isHandsFreeMode = false

    // Debounce for Fn key
    private var fnDebounceTask: Task<Void, Never>?
    private var pendingFnKeyState: Bool? = nil
    private var pendingFnEventTime: TimeInterval? = nil

    // Keyboard shortcut state tracking
    private var shortcutKeyPressEventTime: TimeInterval?
    private var isShortcutHandsFreeMode = false
    private var shortcutCurrentKeyState = false
    private var lastShortcutTriggerTime: Date?
    private let shortcutCooldownInterval: TimeInterval = 0.5

    enum RecordingMode: String, CaseIterable {
        case hybrid = "hybrid"
        case pushToTalk = "pushToTalk"
        case toggle = "toggle"

        var displayName: String {
            switch self {
            case .hybrid: return "Hybrid"
            case .pushToTalk: return "Push-to-Talk"
            case .toggle: return "Toggle"
            }
        }
    }

    enum CompanionModifier: String, CaseIterable {
        case none = "none"
        case shift = "shift"
        case control = "control"
        case option = "option"
        case command = "command"
        case fn = "fn"

        var flag: NSEvent.ModifierFlags? {
            switch self {
            case .none: return nil
            case .shift: return .shift
            case .control: return .control
            case .option: return .option
            case .command: return .command
            case .fn: return .function
            }
        }

        var displayName: String {
            switch self {
            case .none: return "None"
            case .shift: return "Shift"
            case .control: return "Control (⌃)"
            case .option: return "Option (⌥)"
            case .command: return "Command (⌘)"
            case .fn: return "Fn"
            }
        }
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

        var modifierFlag: NSEvent.ModifierFlags {
            switch self {
            case .rightOption, .leftOption: return .option
            case .leftControl, .rightControl: return .control
            case .fn: return .function
            case .rightCommand: return .command
            case .rightShift: return .shift
            case .custom, .none: return []
            }
        }

        var isModifierKey: Bool {
            return self != .custom && self != .none
        }
    }
    
    init(whisperState: WhisperState) {
        self.selectedHotkey1 = HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey1") ?? "") ?? .rightCommand
        self.selectedHotkey2 = HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey2") ?? "") ?? .none
        self.companionModifier1 = CompanionModifier(rawValue: UserDefaults.standard.string(forKey: "companionModifier1") ?? "") ?? .none
        self.companionModifier2 = CompanionModifier(rawValue: UserDefaults.standard.string(forKey: "companionModifier2") ?? "") ?? .none
        self.recordingMode = RecordingMode(rawValue: UserDefaults.standard.string(forKey: "recordingMode") ?? "") ?? .hybrid

        self.isMiddleClickToggleEnabled = UserDefaults.standard.bool(forKey: "isMiddleClickToggleEnabled")
        self.middleClickActivationDelay = UserDefaults.standard.integer(forKey: "middleClickActivationDelay")
        
        self.whisperState = whisperState
        self.miniRecorderShortcutManager = MiniRecorderShortcutManager(whisperState: whisperState)
        self.powerModeShortcutManager = PowerModeShortcutManager(whisperState: whisperState)

        KeyboardShortcuts.onKeyUp(for: .pasteLastTranscription) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.pasteLastTranscription(from: self.whisperState.modelContext)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .pasteLastEnhancement) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.pasteLastEnhancement(from: self.whisperState.modelContext)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .retryLastTranscription) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.retryLastTranscription(from: self.whisperState.modelContext, whisperState: self.whisperState)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .openHistoryWindow) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                HistoryWindowController.shared.showHistoryWindow(
                    modelContainer: self.whisperState.modelContext.container,
                    whisperState: self.whisperState
                )
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.setupHotkeyMonitoring()
        }
    }
    
    private func setupHotkeyMonitoring() {
        removeAllMonitoring()
        
        setupModifierKeyMonitoring()
        setupCustomShortcutMonitoring()
        setupMiddleClickMonitoring()
    }
    
    private func setupModifierKeyMonitoring() {
        // Only set up if at least one hotkey is a modifier key
        guard (selectedHotkey1.isModifierKey && selectedHotkey1 != .none) || (selectedHotkey2.isModifierKey && selectedHotkey2 != .none) else { return }

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
    
    private func setupMiddleClickMonitoring() {
        guard isMiddleClickToggleEnabled else { return }

        // Mouse Down
        let downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }

            self.middleClickTask?.cancel()
            self.middleClickTask = Task {
                do {
                    let delay = UInt64(self.middleClickActivationDelay) * 1_000_000 // ms to ns
                    try await Task.sleep(nanoseconds: delay)
                    
                    guard self.isMiddleClickToggleEnabled, !Task.isCancelled else { return }
                    
                    Task { @MainActor in
                        guard self.canProcessHotkeyAction else { return }
                        await self.whisperState.toggleMiniRecorder()
                    }
                } catch {
                    // Cancelled
                }
            }
        }

        // Mouse Up
        let upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }
            self.middleClickTask?.cancel()
        }

        middleClickMonitors = [downMonitor, upMonitor]
    }
    
    private func setupCustomShortcutMonitoring() {
        if selectedHotkey1 == .custom {
            KeyboardShortcuts.onKeyDown(for: .toggleMiniRecorder) { [weak self] in
                let eventTime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in await self?.handleCustomShortcutKeyDown(eventTime: eventTime) }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleMiniRecorder) { [weak self] in
                let eventTime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in await self?.handleCustomShortcutKeyUp(eventTime: eventTime) }
            }
        }
        if selectedHotkey2 == .custom {
            KeyboardShortcuts.onKeyDown(for: .toggleMiniRecorder2) { [weak self] in
                let eventTime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in await self?.handleCustomShortcutKeyDown(eventTime: eventTime) }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleMiniRecorder2) { [weak self] in
                let eventTime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in await self?.handleCustomShortcutKeyUp(eventTime: eventTime) }
            }
        }
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
        
        for monitor in middleClickMonitors {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        middleClickMonitors = []
        middleClickTask?.cancel()
        
        resetKeyStates()
    }
    
    private func resetKeyStates() {
        currentKeyState = false
        keyPressEventTime = nil
        isHandsFreeMode = false
        shortcutCurrentKeyState = false
        shortcutKeyPressEventTime = nil
        isShortcutHandsFreeMode = false
    }
    
    private func handleModifierKeyEvent(_ event: NSEvent) async {
        let keycode = event.keyCode
        let flags = event.modifierFlags
        let eventTime = event.timestamp

        // Determine which hotkey slot this event relates to.
        // Match on primary hotkey keycode, OR on companion modifier change
        // while the primary is already held.
        let activeHotkey: HotkeyOption?
        let activeCompanion: CompanionModifier

        if selectedHotkey1.isModifierKey && selectedHotkey1 != .none && selectedHotkey1.keyCode == keycode {
            activeHotkey = selectedHotkey1
            activeCompanion = companionModifier1
        } else if selectedHotkey2.isModifierKey && selectedHotkey2 != .none && selectedHotkey2.keyCode == keycode {
            activeHotkey = selectedHotkey2
            activeCompanion = companionModifier2
        } else if selectedHotkey1.isModifierKey && selectedHotkey1 != .none && companionModifier1 != .none && flags.contains(selectedHotkey1.modifierFlag) {
            // Primary for hotkey1 is still held; this event is the companion changing
            activeHotkey = selectedHotkey1
            activeCompanion = companionModifier1
        } else if selectedHotkey2.isModifierKey && selectedHotkey2 != .none && companionModifier2 != .none && flags.contains(selectedHotkey2.modifierFlag) {
            activeHotkey = selectedHotkey2
            activeCompanion = companionModifier2
        } else {
            return
        }

        guard let hotkey = activeHotkey else { return }

        let isComboActive = isModifierComboSatisfied(hotkey: hotkey, companion: activeCompanion, flags: flags)

        // Apply Fn debounce when Fn is involved (as primary or companion)
        if hotkey == .fn || activeCompanion == .fn {
            pendingFnKeyState = isComboActive
            pendingFnEventTime = eventTime
            fnDebounceTask?.cancel()
            fnDebounceTask = Task { [pendingState = isComboActive, pendingTime = eventTime] in
                try? await Task.sleep(nanoseconds: 40_000_000) // 40ms
                if self.pendingFnKeyState == pendingState {
                    await self.processKeyPress(isKeyPressed: pendingState, eventTime: pendingTime)
                }
            }
            return
        }

        await processKeyPress(isKeyPressed: isComboActive, eventTime: eventTime)
    }

    private func isModifierComboSatisfied(hotkey: HotkeyOption, companion: CompanionModifier, flags: NSEvent.ModifierFlags) -> Bool {
        // Primary modifier must be held
        guard flags.contains(hotkey.modifierFlag) else { return false }

        // Companion modifier must be held (if configured)
        if let companionFlag = companion.flag {
            guard flags.contains(companionFlag) else { return false }
        }

        // No extra modifiers beyond what we expect
        let significantFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command, .function]
        let activeFlags = flags.intersection(significantFlags)
        var expectedFlags: NSEvent.ModifierFlags = [hotkey.modifierFlag]
        if let companionFlag = companion.flag {
            expectedFlags.insert(companionFlag)
        }

        return activeFlags == expectedFlags
    }
    
    private func processKeyPress(isKeyPressed: Bool, eventTime: TimeInterval) async {
        guard isKeyPressed != currentKeyState else { return }
        currentKeyState = isKeyPressed

        switch recordingMode {
        case .pushToTalk:
            if isKeyPressed {
                if !whisperState.isMiniRecorderVisible {
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: starting recording (push-to-talk key down)")
                    await whisperState.toggleMiniRecorder()
                }
            } else {
                if whisperState.isMiniRecorderVisible {
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: stopping recording (push-to-talk key up)")
                    await whisperState.toggleMiniRecorder()
                }
            }

        case .toggle:
            if isKeyPressed {
                guard canProcessHotkeyAction else { return }
                logger.notice("processKeyPress: toggling mini recorder (toggle mode)")
                await whisperState.toggleMiniRecorder()
            }

        case .hybrid:
            if isKeyPressed {
                keyPressEventTime = eventTime

                if isHandsFreeMode {
                    isHandsFreeMode = false
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: toggling mini recorder (hands-free toggle)")
                    await whisperState.toggleMiniRecorder()
                    return
                }

                if !whisperState.isMiniRecorderVisible {
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: toggling mini recorder (key down while not visible)")
                    await whisperState.toggleMiniRecorder()
                }
            } else {
                if let startTime = keyPressEventTime {
                    let pressDuration = eventTime - startTime

                    if pressDuration < briefPressThreshold {
                        isHandsFreeMode = true
                    } else {
                        guard canProcessHotkeyAction else { return }
                        logger.notice("processKeyPress: toggling mini recorder (key up long press)")
                        await whisperState.toggleMiniRecorder()
                    }
                }

                keyPressEventTime = nil
            }
        }
    }
    
    private func handleCustomShortcutKeyDown(eventTime: TimeInterval) async {
        if let lastTrigger = lastShortcutTriggerTime,
           Date().timeIntervalSince(lastTrigger) < shortcutCooldownInterval {
            return
        }

        guard !shortcutCurrentKeyState else { return }
        shortcutCurrentKeyState = true
        lastShortcutTriggerTime = Date()
        shortcutKeyPressEventTime = eventTime

        switch recordingMode {
        case .pushToTalk:
            if !whisperState.isMiniRecorderVisible {
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyDown: starting recording (push-to-talk)")
                await whisperState.toggleMiniRecorder()
            }

        case .toggle:
            guard canProcessHotkeyAction else { return }
            logger.notice("handleCustomShortcutKeyDown: toggling mini recorder (toggle mode)")
            await whisperState.toggleMiniRecorder()

        case .hybrid:
            if isShortcutHandsFreeMode {
                isShortcutHandsFreeMode = false
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyDown: toggling mini recorder (hands-free toggle)")
                await whisperState.toggleMiniRecorder()
                return
            }

            if !whisperState.isMiniRecorderVisible {
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyDown: toggling mini recorder (key down while not visible)")
                await whisperState.toggleMiniRecorder()
            }
        }
    }

    private func handleCustomShortcutKeyUp(eventTime: TimeInterval) async {
        guard shortcutCurrentKeyState else { return }
        shortcutCurrentKeyState = false

        switch recordingMode {
        case .pushToTalk:
            if whisperState.isMiniRecorderVisible {
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyUp: stopping recording (push-to-talk)")
                await whisperState.toggleMiniRecorder()
            }

        case .toggle:
            break // Nothing to do on key up in toggle mode

        case .hybrid:
            if let startTime = shortcutKeyPressEventTime {
                let pressDuration = eventTime - startTime

                if pressDuration < briefPressThreshold {
                    isShortcutHandsFreeMode = true
                } else {
                    guard canProcessHotkeyAction else { return }
                    logger.notice("handleCustomShortcutKeyUp: toggling mini recorder (key up long press)")
                    await whisperState.toggleMiniRecorder()
                }
            }
        }

        shortcutKeyPressEventTime = nil
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
