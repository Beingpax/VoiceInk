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
    @Published private(set) var shortcutProfilesEnabled: Bool
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
    private var legacySettings: LegacyActivationShortcutSettings
    private var isApplyingActivationSettings = false
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
        let initialLegacySettings = Self.loadLegacyActivationSettings()
        let initialProfilesState = Self.loadPersistedProfilesState()
        let initialShortcutProfilesEnabled = UserDefaults.standard.shortcutProfilesEnabled

        var initialProfiles = initialProfilesState?.profiles ?? []
        var initialActiveProfileID = initialProfilesState?.activeProfileID

        let initialEffectiveSettings: LegacyActivationShortcutSettings
        if initialShortcutProfilesEnabled {
            if initialProfiles.isEmpty {
                let seededState = ActivationShortcutProfilesState.makeDefaultState(from: initialLegacySettings)
                initialProfiles = seededState.profiles
                initialActiveProfileID = seededState.activeProfileID
            }

            let initialActiveProfile =
                initialProfiles.first(where: { $0.id == initialActiveProfileID }) ?? initialProfiles.first
            initialEffectiveSettings = initialActiveProfile?.makeLegacySettings() ?? initialLegacySettings
        } else {
            initialEffectiveSettings = initialLegacySettings
        }

        self.legacySettings = initialLegacySettings
        self.profiles = initialProfiles
        self.activeProfileID = initialActiveProfileID
        self.shortcutProfilesEnabled = initialShortcutProfilesEnabled
        self.selectedHotkey1 = initialEffectiveSettings.selectedHotkey1
        self.selectedHotkey2 = initialEffectiveSettings.selectedHotkey2
        self.hotkeyMode1 = initialEffectiveSettings.hotkeyMode1
        self.hotkeyMode2 = initialEffectiveSettings.hotkeyMode2

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

        persistLegacySettings()
        persistProfilesState()
        applyEffectiveSettings(initialEffectiveSettings, shouldPostSettingsChange: false)

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
        currentCustomShortcut(for: .primary)
    }

    var secondaryCustomShortcut: KeyboardShortcuts.Shortcut? {
        currentCustomShortcut(for: .secondary)
    }

    var legacyActivationSettings: LegacyActivationShortcutSettings {
        legacySettings
    }

    func setShortcutProfilesEnabled(_ enabled: Bool) {
        guard shortcutProfilesEnabled != enabled else { return }
        shortcutProfilesEnabled = enabled
        applyCurrentModeSettings()
    }

    func switchProfile(to id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }

        if shortcutProfilesEnabled {
            applyProfile(profile)
        } else {
            activeProfileID = profile.id
            persistProfilesState()
        }
    }

    func createProfileFromCurrent(name: String? = nil) {
        var newProfile = currentEffectiveSettings().makeDefaultProfile()
        newProfile.id = UUID()
        newProfile.name = uniqueProfileName(for: name ?? "New Profile")

        profiles.append(newProfile)
        if shortcutProfilesEnabled {
            applyProfile(newProfile)
        } else {
            activeProfileID = newProfile.id
            persistProfilesState()
        }
    }

    func duplicateActiveProfile() {
        let sourceProfile = activeProfile ?? currentEffectiveSettings().makeDefaultProfile()
        var duplicatedProfile = sourceProfile
        duplicatedProfile.id = UUID()
        duplicatedProfile.name = uniqueProfileName(for: "\(sourceProfile.name) Copy")

        profiles.append(duplicatedProfile)
        if shortcutProfilesEnabled {
            applyProfile(duplicatedProfile)
        } else {
            activeProfileID = duplicatedProfile.id
            persistProfilesState()
        }
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

        let deletingActiveProfile = activeProfileID == id

        var updatedProfiles = profiles
        updatedProfiles.remove(at: index)

        let fallbackProfileID: UUID?
        if deletingActiveProfile {
            if index < updatedProfiles.count {
                fallbackProfileID = updatedProfiles[index].id
            } else {
                fallbackProfileID = updatedProfiles.last?.id
            }
        } else {
            fallbackProfileID = activeProfileID
        }

        let normalizedState = ActivationShortcutProfilesState(
            profiles: updatedProfiles,
            activeProfileID: fallbackProfileID
        )
        profiles = normalizedState.profiles
        activeProfileID = normalizedState.activeProfileID
        persistProfilesState()

        if shortcutProfilesEnabled && deletingActiveProfile,
           let fallbackProfile = activeProfile {
            applyProfile(fallbackProfile)
        }
    }

    func setCustomShortcut(_ shortcut: KeyboardShortcuts.Shortcut?, for slot: ActivationSlot) {
        switch slot {
        case .primary:
            if selectedHotkey1 == .custom {
                KeyboardShortcuts.setShortcut(shortcut, for: .toggleMiniRecorder)
            }
        case .secondary:
            if selectedHotkey2 == .custom {
                KeyboardShortcuts.setShortcut(shortcut, for: .toggleMiniRecorder2)
            }
        }

        if shortcutProfilesEnabled {
            ensureSavedProfilesState()
            guard let activeProfileIndex else { return }

            var updatedProfiles = profiles
            switch slot {
            case .primary:
                updatedProfiles[activeProfileIndex].toggleMiniRecorderShortcut = shortcut
            case .secondary:
                updatedProfiles[activeProfileIndex].toggleMiniRecorderShortcut2 = shortcut
            }

            profiles = updatedProfiles
            persistProfilesState()
        } else {
            switch slot {
            case .primary:
                legacySettings.toggleMiniRecorderShortcut = shortcut
            case .secondary:
                legacySettings.toggleMiniRecorderShortcut2 = shortcut
            }

            persistLegacySettings()
        }

        setupHotkeyMonitoring()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    func importActivationSettings(
        legacySettings: LegacyActivationShortcutSettings,
        shortcutProfiles: [ActivationShortcutProfile],
        activeProfileID: UUID?,
        shortcutProfilesEnabled: Bool
    ) {
        self.legacySettings = legacySettings

        if shortcutProfiles.isEmpty {
            profiles = []
            self.activeProfileID = nil
        } else {
            let importedState = ActivationShortcutProfilesState(
                profiles: shortcutProfiles,
                activeProfileID: activeProfileID
            )
            profiles = importedState.profiles
            self.activeProfileID = importedState.activeProfileID
        }

        self.shortcutProfilesEnabled = shortcutProfilesEnabled
        persistLegacySettings()
        persistProfilesState()
        applyCurrentModeSettings(shouldPersistModeFlag: true, shouldPostSettingsChange: true)
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
        guard !isApplyingActivationSettings else { return }

        updateLiveCustomShortcutsForCurrentState()
        if shortcutProfilesEnabled {
            ensureSavedProfilesState()
            syncActiveProfileFromCurrentState()
            persistProfilesState()
        } else {
            syncLegacySettingsFromCurrentState()
            persistLegacySettings()
        }
        setupHotkeyMonitoring()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private func updateLiveCustomShortcutsForCurrentState() {
        let primaryShortcut = selectedHotkey1 == .custom ? currentCustomShortcut(for: .primary) : nil
        let secondaryShortcut = selectedHotkey2 == .custom ? currentCustomShortcut(for: .secondary) : nil

        KeyboardShortcuts.setShortcut(primaryShortcut, for: .toggleMiniRecorder)
        KeyboardShortcuts.setShortcut(secondaryShortcut, for: .toggleMiniRecorder2)
    }

    private func syncActiveProfileFromCurrentState() {
        ensureSavedProfilesState()
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

    private func syncLegacySettingsFromCurrentState() {
        legacySettings.selectedHotkey1 = selectedHotkey1
        legacySettings.selectedHotkey2 = selectedHotkey2
        legacySettings.hotkeyMode1 = hotkeyMode1
        legacySettings.hotkeyMode2 = hotkeyMode2

        if selectedHotkey1 == .custom {
            legacySettings.toggleMiniRecorderShortcut = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)
        }

        if selectedHotkey2 == .custom {
            legacySettings.toggleMiniRecorderShortcut2 = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder2)
        }
    }

    private func applyProfile(
        _ profile: ActivationShortcutProfile,
        shouldPersist: Bool = true,
        shouldPostSettingsChange: Bool = true
    ) {
        activeProfileID = profile.id
        applyEffectiveSettings(profile.makeLegacySettings(), shouldPostSettingsChange: false)

        if shouldPersist {
            persistProfilesState()
        }

        if shouldPostSettingsChange {
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    private func applyLegacySettings(
        _ settings: LegacyActivationShortcutSettings,
        shouldPersist: Bool = true,
        shouldPostSettingsChange: Bool = true
    ) {
        legacySettings = settings
        applyEffectiveSettings(settings, shouldPostSettingsChange: false)

        if shouldPersist {
            persistLegacySettings()
        }

        if shouldPostSettingsChange {
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    private func applyCurrentModeSettings(
        shouldPersistModeFlag: Bool = true,
        shouldPostSettingsChange: Bool = true
    ) {
        if shouldPersistModeFlag {
            UserDefaults.standard.shortcutProfilesEnabled = shortcutProfilesEnabled
        }

        if shortcutProfilesEnabled {
            ensureSavedProfilesState()
            if let profile = activeProfile {
                applyProfile(
                    profile,
                    shouldPersist: true,
                    shouldPostSettingsChange: shouldPostSettingsChange
                )
            }
        } else {
            applyLegacySettings(
                legacySettings,
                shouldPersist: true,
                shouldPostSettingsChange: shouldPostSettingsChange
            )
        }
    }

    private func applyEffectiveSettings(
        _ settings: LegacyActivationShortcutSettings,
        shouldPostSettingsChange: Bool = true
    ) {
        isApplyingActivationSettings = true
        selectedHotkey1 = settings.selectedHotkey1
        selectedHotkey2 = settings.selectedHotkey2
        hotkeyMode1 = settings.hotkeyMode1
        hotkeyMode2 = settings.hotkeyMode2
        isApplyingActivationSettings = false

        KeyboardShortcuts.setShortcut(
            settings.selectedHotkey1 == .custom ? settings.toggleMiniRecorderShortcut : nil,
            for: .toggleMiniRecorder
        )
        KeyboardShortcuts.setShortcut(
            settings.selectedHotkey2 == .custom ? settings.toggleMiniRecorderShortcut2 : nil,
            for: .toggleMiniRecorder2
        )

        setupHotkeyMonitoring()

        if shouldPostSettingsChange {
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    private func ensureSavedProfilesState() {
        if profiles.isEmpty {
            let seededState = ActivationShortcutProfilesState.makeDefaultState(from: legacySettings)
            profiles = seededState.profiles
            activeProfileID = seededState.activeProfileID
            return
        }

        let normalizedState = ActivationShortcutProfilesState(
            profiles: profiles,
            activeProfileID: activeProfileID
        )
        profiles = normalizedState.profiles
        activeProfileID = normalizedState.activeProfileID
    }

    private func persistLegacySettings() {
        UserDefaults.standard.set(legacySettings.selectedHotkey1.rawValue, forKey: "selectedHotkey1")
        UserDefaults.standard.set(legacySettings.selectedHotkey2.rawValue, forKey: "selectedHotkey2")
        UserDefaults.standard.set(legacySettings.hotkeyMode1.rawValue, forKey: "hotkeyMode1")
        UserDefaults.standard.set(legacySettings.hotkeyMode2.rawValue, forKey: "hotkeyMode2")
        UserDefaults.standard.legacyToggleMiniRecorderShortcutData = Self.encodeShortcutData(legacySettings.toggleMiniRecorderShortcut)
        UserDefaults.standard.legacyToggleMiniRecorderShortcut2Data = Self.encodeShortcutData(legacySettings.toggleMiniRecorderShortcut2)
    }

    private func persistProfilesState() {
        guard !profiles.isEmpty else {
            UserDefaults.standard.activationShortcutProfilesData = nil
            UserDefaults.standard.activeActivationShortcutProfileID = nil
            return
        }

        let normalizedState = ActivationShortcutProfilesState(
            profiles: profiles,
            activeProfileID: activeProfileID
        )
        profiles = normalizedState.profiles
        activeProfileID = normalizedState.activeProfileID

        if let data = try? JSONEncoder().encode(normalizedState.profiles) {
            UserDefaults.standard.activationShortcutProfilesData = data
        }
        UserDefaults.standard.activeActivationShortcutProfileID = normalizedState.activeProfileID.uuidString
    }

    private func currentCustomShortcut(for slot: ActivationSlot) -> KeyboardShortcuts.Shortcut? {
        if shortcutProfilesEnabled {
            switch slot {
            case .primary:
                return activeProfile?.toggleMiniRecorderShortcut
            case .secondary:
                return activeProfile?.toggleMiniRecorderShortcut2
            }
        }

        switch slot {
        case .primary:
            return legacySettings.toggleMiniRecorderShortcut
        case .secondary:
            return legacySettings.toggleMiniRecorderShortcut2
        }
    }

    private func currentEffectiveSettings() -> LegacyActivationShortcutSettings {
        LegacyActivationShortcutSettings(
            selectedHotkey1: selectedHotkey1,
            selectedHotkey2: selectedHotkey2,
            hotkeyMode1: hotkeyMode1,
            hotkeyMode2: hotkeyMode2,
            toggleMiniRecorderShortcut: KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder),
            toggleMiniRecorderShortcut2: KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder2)
        )
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

    private static func loadPersistedProfilesState() -> ActivationShortcutProfilesState? {
        if let data = UserDefaults.standard.activationShortcutProfilesData,
           let decodedProfiles = try? JSONDecoder().decode([ActivationShortcutProfile].self, from: data),
           !decodedProfiles.isEmpty {
            return ActivationShortcutProfilesState(
                profiles: decodedProfiles,
                activeProfileID: UserDefaults.standard.activeActivationShortcutProfileID.flatMap(UUID.init(uuidString:))
            )
        }

        return nil
    }

    private static func loadLegacyActivationSettings() -> LegacyActivationShortcutSettings {
        LegacyActivationShortcutSettings(
            selectedHotkey1: HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey1") ?? "") ?? .rightCommand,
            selectedHotkey2: HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey2") ?? "") ?? .none,
            hotkeyMode1: HotkeyMode(rawValue: UserDefaults.standard.string(forKey: "hotkeyMode1") ?? "") ?? .hybrid,
            hotkeyMode2: HotkeyMode(rawValue: UserDefaults.standard.string(forKey: "hotkeyMode2") ?? "") ?? .hybrid,
            toggleMiniRecorderShortcut: decodeShortcutData(
                UserDefaults.standard.legacyToggleMiniRecorderShortcutData
            ) ?? KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder),
            toggleMiniRecorderShortcut2: decodeShortcutData(
                UserDefaults.standard.legacyToggleMiniRecorderShortcut2Data
            ) ?? KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder2)
        )
    }

    private static func encodeShortcutData(_ shortcut: KeyboardShortcuts.Shortcut?) -> Data? {
        guard let shortcut else { return nil }
        return try? JSONEncoder().encode(shortcut)
    }

    private static func decodeShortcutData(_ data: Data?) -> KeyboardShortcuts.Shortcut? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(KeyboardShortcuts.Shortcut.self, from: data)
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
