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
    enum ActivationSlot {
        case primary
        case secondary
    }

    @Published private(set) var profiles: [ActivationShortcutProfile]
    @Published private(set) var activeProfileID: UUID?
    @Published var selectedHotkey1: HotkeyOption {
        didSet {
            handleActivationConfigurationDidChange()
        }
    }
    @Published var selectedHotkey2: HotkeyOption {
        didSet {
            handleActivationConfigurationDidChange()
        }
    }
    @Published var hotkeyMode1: HotkeyMode {
        didSet {
            handleActivationConfigurationDidChange()
        }
    }
    @Published var hotkeyMode2: HotkeyMode {
        didSet {
            handleActivationConfigurationDidChange()
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
    private var engine: VoiceInkEngine
    private var recorderUIManager: RecorderUIManager
    private var miniRecorderShortcutManager: MiniRecorderShortcutManager
    private var powerModeShortcutManager: PowerModeShortcutManager

    // MARK: - Helper Properties
    private var canProcessHotkeyAction: Bool {
        engine.recordingState != .transcribing && engine.recordingState != .enhancing && engine.recordingState != .busy
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
    private var isApplyingProfile = false
    private var didFinishLaunching = false

    private static let hybridPressThreshold: TimeInterval = 0.5

    enum HotkeyMode: String, CaseIterable, Codable {
        case toggle = "toggle"
        case pushToTalk = "pushToTalk"
        case hybrid = "hybrid"

        var displayName: String {
            switch self {
            case .toggle: return "Toggle"
            case .pushToTalk: return "Push to Talk"
            case .hybrid: return "Hybrid"
            }
        }
    }

    enum HotkeyOption: String, CaseIterable, Codable {
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
    
    init(engine: VoiceInkEngine, recorderUIManager: RecorderUIManager) {
        let initialProfileState = Self.loadInitialProfileState()
        let initialProfile = initialProfileState.activeProfile ?? LegacyActivationShortcutSettings(
            selectedHotkey1: .rightCommand,
            selectedHotkey2: .none,
            hotkeyMode1: .hybrid,
            hotkeyMode2: .hybrid,
            toggleMiniRecorderShortcut: nil,
            toggleMiniRecorderShortcut2: nil
        ).makeDefaultProfile()

        self.profiles = initialProfileState.profiles
        self.activeProfileID = initialProfileState.activeProfileID
        self.selectedHotkey1 = initialProfile.selectedHotkey1
        self.selectedHotkey2 = initialProfile.selectedHotkey2
        self.hotkeyMode1 = initialProfile.hotkeyMode1
        self.hotkeyMode2 = initialProfile.hotkeyMode2

        self.isMiddleClickToggleEnabled = UserDefaults.standard.bool(forKey: "isMiddleClickToggleEnabled")
        self.middleClickActivationDelay = UserDefaults.standard.integer(forKey: "middleClickActivationDelay")

        self.engine = engine
        self.recorderUIManager = recorderUIManager
        self.miniRecorderShortcutManager = MiniRecorderShortcutManager(engine: engine, recorderUIManager: recorderUIManager)
        self.powerModeShortcutManager = PowerModeShortcutManager(engine: engine)

        KeyboardShortcuts.onKeyUp(for: .pasteLastTranscription) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.pasteLastTranscription(from: self.engine.modelContext)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .pasteLastEnhancement) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.pasteLastEnhancement(from: self.engine.modelContext)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .retryLastTranscription) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.retryLastTranscription(
                    from: self.engine.modelContext,
                    transcriptionModelManager: self.engine.transcriptionModelManager,
                    serviceRegistry: self.engine.serviceRegistry,
                    enhancementService: self.engine.enhancementService
                )
            }
        }

        KeyboardShortcuts.onKeyUp(for: .openHistoryWindow) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                HistoryWindowController.shared.showHistoryWindow(
                    modelContainer: self.engine.modelContext.container,
                    engine: self.engine
                )
            }
        }

        applyProfile(
            initialProfile,
            shouldPersist: true,
            shouldPostSettingsChange: false
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidFinishLaunching),
            name: NSApplication.didFinishLaunchingNotification,
            object: nil
        )
    }

    @objc private func appDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didFinishLaunchingNotification, object: nil)
        didFinishLaunching = true
        setupHotkeyMonitoring()
    }

    var activeProfile: ActivationShortcutProfile? {
        guard let activeProfileID else {
            return profiles.first
        }

        return profiles.first { $0.id == activeProfileID } ?? profiles.first
    }

    var activeProfileName: String {
        activeProfile?.name ?? "Default"
    }

    var hasAnyActivationShortcut: Bool {
        isActivationSlotConfigured(.primary) || isActivationSlotConfigured(.secondary)
    }

    var primaryCustomShortcut: KeyboardShortcuts.Shortcut? {
        activeProfile?.toggleMiniRecorderShortcut
    }

    var secondaryCustomShortcut: KeyboardShortcuts.Shortcut? {
        activeProfile?.toggleMiniRecorderShortcut2
    }

    func switchProfile(to id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        applyProfile(profile)
    }

    func createProfileFromCurrent(name: String? = nil) {
        guard let activeProfile else { return }

        var newProfile = activeProfile
        newProfile.id = UUID()
        newProfile.name = uniqueProfileName(for: name ?? "New Profile")

        profiles.append(newProfile)
        applyProfile(newProfile)
    }

    func duplicateActiveProfile() {
        guard let activeProfile else { return }

        var duplicatedProfile = activeProfile
        duplicatedProfile.id = UUID()
        duplicatedProfile.name = uniqueProfileName(for: "\(activeProfile.name) Copy")

        profiles.append(duplicatedProfile)
        applyProfile(duplicatedProfile)
    }

    func renameActiveProfile(to name: String) {
        guard let activeProfileIndex else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let currentProfile = profiles[activeProfileIndex]
        let uniqueName = uniqueProfileName(for: trimmedName, excluding: currentProfile.id)

        var updatedProfiles = profiles
        updatedProfiles[activeProfileIndex].name = uniqueName
        profiles = updatedProfiles
        persistProfilesState()
    }

    func deleteProfile(with id: UUID) {
        guard profiles.count > 1,
              let index = profiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let fallbackProfile: ActivationShortcutProfile?
        if activeProfileID == id {
            if index < profiles.count - 1 {
                fallbackProfile = profiles[index + 1]
            } else {
                fallbackProfile = profiles[index - 1]
            }
        } else {
            fallbackProfile = activeProfile
        }

        var updatedProfiles = profiles
        updatedProfiles.remove(at: index)
        profiles = updatedProfiles

        if let fallbackProfile {
            applyProfile(fallbackProfile)
        } else {
            persistProfilesState()
        }
    }

    func setCustomShortcut(_ shortcut: KeyboardShortcuts.Shortcut?, for slot: ActivationSlot) {
        guard let activeProfileIndex else { return }

        var updatedProfiles = profiles
        switch slot {
        case .primary:
            updatedProfiles[activeProfileIndex].toggleMiniRecorderShortcut = shortcut
            if selectedHotkey1 == .custom {
                KeyboardShortcuts.setShortcut(shortcut, for: .toggleMiniRecorder)
            }
        case .secondary:
            updatedProfiles[activeProfileIndex].toggleMiniRecorderShortcut2 = shortcut
            if selectedHotkey2 == .custom {
                KeyboardShortcuts.setShortcut(shortcut, for: .toggleMiniRecorder2)
            }
        }

        profiles = updatedProfiles
        persistProfilesState()
        setupHotkeyMonitoring()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    func importProfiles(_ importedProfiles: [ActivationShortcutProfile], activeProfileID: UUID?) {
        let importedState = ActivationShortcutProfilesState(
            profiles: importedProfiles,
            activeProfileID: activeProfileID
        )

        profiles = importedState.profiles
        if let profile = importedState.activeProfile {
            applyProfile(profile)
        }
    }

    func importLegacyActivationSettings(
        selectedHotkey1: HotkeyOption,
        selectedHotkey2: HotkeyOption,
        hotkeyMode1: HotkeyMode,
        hotkeyMode2: HotkeyMode,
        toggleMiniRecorderShortcut: KeyboardShortcuts.Shortcut?,
        toggleMiniRecorderShortcut2: KeyboardShortcuts.Shortcut?
    ) {
        guard let activeProfileIndex else { return }

        var updatedProfiles = profiles
        updatedProfiles[activeProfileIndex].selectedHotkey1 = selectedHotkey1
        updatedProfiles[activeProfileIndex].selectedHotkey2 = selectedHotkey2
        updatedProfiles[activeProfileIndex].hotkeyMode1 = hotkeyMode1
        updatedProfiles[activeProfileIndex].hotkeyMode2 = hotkeyMode2
        updatedProfiles[activeProfileIndex].toggleMiniRecorderShortcut = toggleMiniRecorderShortcut
        updatedProfiles[activeProfileIndex].toggleMiniRecorderShortcut2 = toggleMiniRecorderShortcut2
        profiles = updatedProfiles

        applyProfile(updatedProfiles[activeProfileIndex])
    }
    
    private func setupHotkeyMonitoring() {
        guard didFinishLaunching else { return }
        removeAllMonitoring()
        
        setupModifierKeyMonitoring()
        setupCustomShortcutMonitoring()
        setupMiddleClickMonitoring()
    }
    
    private var activeProfileIndex: Int? {
        guard let activeProfileID else {
            return profiles.isEmpty ? nil : 0
        }

        return profiles.firstIndex(where: { $0.id == activeProfileID }) ?? (profiles.isEmpty ? nil : 0)
    }

    private func handleActivationConfigurationDidChange() {
        guard !isApplyingProfile else { return }

        updateLiveCustomShortcutsForCurrentState()
        syncActiveProfileFromCurrentState()
        persistProfilesState()
        setupHotkeyMonitoring()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private func updateLiveCustomShortcutsForCurrentState() {
        let primaryShortcut = selectedHotkey1 == .custom ? activeProfile?.toggleMiniRecorderShortcut : nil
        let secondaryShortcut = selectedHotkey2 == .custom ? activeProfile?.toggleMiniRecorderShortcut2 : nil

        KeyboardShortcuts.setShortcut(primaryShortcut, for: .toggleMiniRecorder)
        KeyboardShortcuts.setShortcut(secondaryShortcut, for: .toggleMiniRecorder2)
    }

    private func syncActiveProfileFromCurrentState() {
        guard let activeProfileIndex else { return }

        var updatedProfiles = profiles
        updatedProfiles[activeProfileIndex].selectedHotkey1 = selectedHotkey1
        updatedProfiles[activeProfileIndex].selectedHotkey2 = selectedHotkey2
        updatedProfiles[activeProfileIndex].hotkeyMode1 = hotkeyMode1
        updatedProfiles[activeProfileIndex].hotkeyMode2 = hotkeyMode2

        if selectedHotkey1 == .custom {
            updatedProfiles[activeProfileIndex].toggleMiniRecorderShortcut = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)
        }

        if selectedHotkey2 == .custom {
            updatedProfiles[activeProfileIndex].toggleMiniRecorderShortcut2 = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder2)
        }

        profiles = updatedProfiles
    }

    private func applyProfile(
        _ profile: ActivationShortcutProfile,
        shouldPersist: Bool = true,
        shouldPostSettingsChange: Bool = true
    ) {
        isApplyingProfile = true
        activeProfileID = profile.id
        selectedHotkey1 = profile.selectedHotkey1
        selectedHotkey2 = profile.selectedHotkey2
        hotkeyMode1 = profile.hotkeyMode1
        hotkeyMode2 = profile.hotkeyMode2
        isApplyingProfile = false

        KeyboardShortcuts.setShortcut(
            profile.selectedHotkey1 == .custom ? profile.toggleMiniRecorderShortcut : nil,
            for: .toggleMiniRecorder
        )
        KeyboardShortcuts.setShortcut(
            profile.selectedHotkey2 == .custom ? profile.toggleMiniRecorderShortcut2 : nil,
            for: .toggleMiniRecorder2
        )

        mirrorActiveProfileToLegacyDefaults()

        if shouldPersist {
            persistProfilesState()
        }

        setupHotkeyMonitoring()

        if shouldPostSettingsChange {
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    private func mirrorActiveProfileToLegacyDefaults() {
        UserDefaults.standard.set(selectedHotkey1.rawValue, forKey: "selectedHotkey1")
        UserDefaults.standard.set(selectedHotkey2.rawValue, forKey: "selectedHotkey2")
        UserDefaults.standard.set(hotkeyMode1.rawValue, forKey: "hotkeyMode1")
        UserDefaults.standard.set(hotkeyMode2.rawValue, forKey: "hotkeyMode2")
    }

    private func persistProfilesState() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.activationShortcutProfilesData = data
        }
        UserDefaults.standard.activeActivationShortcutProfileID = activeProfileID?.uuidString
        mirrorActiveProfileToLegacyDefaults()
    }

    private func uniqueProfileName(for baseName: String, excluding profileID: UUID? = nil) -> String {
        let trimmedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedBaseName = trimmedBaseName.isEmpty ? "Profile" : trimmedBaseName
        let excludedID = profileID

        var candidate = sanitizedBaseName
        var suffix = 2
        let existingNames = profiles
            .filter { $0.id != excludedID }
            .map { $0.name.lowercased() }

        while existingNames.contains(candidate.lowercased()) {
            candidate = "\(sanitizedBaseName) \(suffix)"
            suffix += 1
        }

        return candidate
    }

    private func isActivationSlotConfigured(_ slot: ActivationSlot) -> Bool {
        switch slot {
        case .primary:
            switch selectedHotkey1 {
            case .none:
                return false
            case .custom:
                return KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) != nil
            default:
                return true
            }
        case .secondary:
            switch selectedHotkey2 {
            case .none:
                return false
            case .custom:
                return KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder2) != nil
            default:
                return true
            }
        }
    }

    private static func loadInitialProfileState() -> ActivationShortcutProfilesState {
        if let data = UserDefaults.standard.activationShortcutProfilesData,
           let decodedProfiles = try? JSONDecoder().decode([ActivationShortcutProfile].self, from: data),
           !decodedProfiles.isEmpty {
            return ActivationShortcutProfilesState(
                profiles: decodedProfiles,
                activeProfileID: UserDefaults.standard.activeActivationShortcutProfileID.flatMap(UUID.init(uuidString:))
            )
        }

        return ActivationShortcutProfilesState.makeDefaultState(
            from: loadLegacyActivationSettings()
        )
    }

    private static func loadLegacyActivationSettings() -> LegacyActivationShortcutSettings {
        LegacyActivationShortcutSettings(
            selectedHotkey1: HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey1") ?? "") ?? .rightCommand,
            selectedHotkey2: HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey2") ?? "") ?? .none,
            hotkeyMode1: HotkeyMode(rawValue: UserDefaults.standard.string(forKey: "hotkeyMode1") ?? "") ?? .hybrid,
            hotkeyMode2: HotkeyMode(rawValue: UserDefaults.standard.string(forKey: "hotkeyMode2") ?? "") ?? .hybrid,
            toggleMiniRecorderShortcut: KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder),
            toggleMiniRecorderShortcut2: KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder2)
        )
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
                        await self.recorderUIManager.toggleMiniRecorder()
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
                Task { @MainActor in await self?.handleCustomShortcutKeyDown(eventTime: eventTime, mode: self?.hotkeyMode1 ?? .toggle) }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleMiniRecorder) { [weak self] in
                let eventTime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in await self?.handleCustomShortcutKeyUp(eventTime: eventTime, mode: self?.hotkeyMode1 ?? .toggle) }
            }
        }
        if selectedHotkey2 == .custom {
            KeyboardShortcuts.onKeyDown(for: .toggleMiniRecorder2) { [weak self] in
                let eventTime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in await self?.handleCustomShortcutKeyDown(eventTime: eventTime, mode: self?.hotkeyMode2 ?? .toggle) }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleMiniRecorder2) { [weak self] in
                let eventTime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in await self?.handleCustomShortcutKeyUp(eventTime: eventTime, mode: self?.hotkeyMode2 ?? .toggle) }
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

        let activeMode: HotkeyMode
        let activeHotkey: HotkeyOption?
        if selectedHotkey1.isModifierKey && selectedHotkey1.keyCode == keycode {
            activeHotkey = selectedHotkey1
            activeMode = hotkeyMode1
        } else if selectedHotkey2.isModifierKey && selectedHotkey2.keyCode == keycode {
            activeHotkey = selectedHotkey2
            activeMode = hotkeyMode2
        } else {
            activeHotkey = nil
            activeMode = .toggle
        }

        guard let hotkey = activeHotkey else { return }

        var isKeyPressed = false

        switch hotkey {
        case .rightOption, .leftOption:
            isKeyPressed = flags.contains(.option)
        case .leftControl, .rightControl:
            isKeyPressed = flags.contains(.control)
        case .fn:
            isKeyPressed = flags.contains(.function)
            pendingFnKeyState = isKeyPressed
            pendingFnEventTime = eventTime
            fnDebounceTask?.cancel()
            fnDebounceTask = Task { [pendingState = isKeyPressed, pendingTime = eventTime] in
                try? await Task.sleep(nanoseconds: 75_000_000) // 75ms
                guard !Task.isCancelled, pendingFnKeyState == pendingState else { return }
                Task { @MainActor in
                    await self.processKeyPress(isKeyPressed: pendingState, eventTime: pendingTime, mode: activeMode)
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

        await processKeyPress(isKeyPressed: isKeyPressed, eventTime: eventTime, mode: activeMode)
    }

    private func processKeyPress(isKeyPressed: Bool, eventTime: TimeInterval, mode: HotkeyMode) async {
        guard isKeyPressed != currentKeyState else { return }
        currentKeyState = isKeyPressed

        if isKeyPressed {
            keyPressEventTime = eventTime

            switch mode {
            case .toggle, .hybrid:
                if isHandsFreeMode {
                    isHandsFreeMode = false
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: toggling mini recorder (hands-free toggle)")
                    await recorderUIManager.toggleMiniRecorder()
                    return
                }

                if !recorderUIManager.isMiniRecorderVisible {
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: toggling mini recorder (key down while not visible)")
                    await recorderUIManager.toggleMiniRecorder()
                }

            case .pushToTalk:
                if !recorderUIManager.isMiniRecorderVisible {
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: starting recording (push-to-talk key down)")
                    await recorderUIManager.toggleMiniRecorder()
                }
            }
        } else {
            switch mode {
            case .toggle:
                isHandsFreeMode = true

            case .pushToTalk:
                if recorderUIManager.isMiniRecorderVisible {
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: stopping recording (push-to-talk key up)")
                    await recorderUIManager.toggleMiniRecorder()
                }

            case .hybrid:
                let pressDuration = keyPressEventTime.map { eventTime - $0 } ?? 0
                if pressDuration >= Self.hybridPressThreshold && engine.recordingState == .recording {
                    guard canProcessHotkeyAction else { return }
                    logger.notice("processKeyPress: stopping recording (hybrid push-to-talk, duration=\(pressDuration, privacy: .public)s)")
                    await recorderUIManager.toggleMiniRecorder()
                } else {
                    isHandsFreeMode = true
                }
            }

            keyPressEventTime = nil
        }
    }
    
    private func handleCustomShortcutKeyDown(eventTime: TimeInterval, mode: HotkeyMode) async {
        if let lastTrigger = lastShortcutTriggerTime,
           Date().timeIntervalSince(lastTrigger) < shortcutCooldownInterval {
            return
        }

        guard !shortcutCurrentKeyState else { return }
        shortcutCurrentKeyState = true
        lastShortcutTriggerTime = Date()
        shortcutKeyPressEventTime = eventTime

        switch mode {
        case .toggle, .hybrid:
            if isShortcutHandsFreeMode {
                isShortcutHandsFreeMode = false
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyDown: toggling mini recorder (hands-free toggle)")
                await recorderUIManager.toggleMiniRecorder()
                return
            }

            if !recorderUIManager.isMiniRecorderVisible {
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyDown: toggling mini recorder (key down while not visible)")
                await recorderUIManager.toggleMiniRecorder()
            }

        case .pushToTalk:
            if !recorderUIManager.isMiniRecorderVisible {
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyDown: starting recording (push-to-talk key down)")
                await recorderUIManager.toggleMiniRecorder()
            }
        }
    }

    private func handleCustomShortcutKeyUp(eventTime: TimeInterval, mode: HotkeyMode) async {
        guard shortcutCurrentKeyState else { return }
        shortcutCurrentKeyState = false

        switch mode {
        case .toggle:
            isShortcutHandsFreeMode = true

        case .pushToTalk:
            if recorderUIManager.isMiniRecorderVisible {
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyUp: stopping recording (push-to-talk key up)")
                await recorderUIManager.toggleMiniRecorder()
            }

        case .hybrid:
            let pressDuration = shortcutKeyPressEventTime.map { eventTime - $0 } ?? 0
            if pressDuration >= Self.hybridPressThreshold && engine.recordingState == .recording {
                guard canProcessHotkeyAction else { return }
                logger.notice("handleCustomShortcutKeyUp: stopping recording (hybrid push-to-talk, duration=\(pressDuration, privacy: .public)s)")
                await recorderUIManager.toggleMiniRecorder()
            } else {
                isShortcutHandsFreeMode = true
            }
        }

        shortcutKeyPressEventTime = nil
    }
    
    // Computed property for backward compatibility with UI
    var isShortcutConfigured: Bool {
        hasAnyActivationShortcut
    }
    
    func updateShortcutStatus() {
        // Called when a custom shortcut changes
        if selectedHotkey1 == .custom {
            setCustomShortcut(KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder), for: .primary)
        }

        if selectedHotkey2 == .custom {
            setCustomShortcut(KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder2), for: .secondary)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)

        Task { @MainActor in
            removeAllMonitoring()
        }
    }
}
