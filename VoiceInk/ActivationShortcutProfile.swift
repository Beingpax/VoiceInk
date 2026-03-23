import Foundation
import KeyboardShortcuts

struct ActivationShortcutProfile: Codable, Identifiable {
    var id: UUID
    var name: String
    var selectedHotkey1: HotkeyManager.HotkeyOption
    var selectedHotkey2: HotkeyManager.HotkeyOption
    var hotkeyMode1: HotkeyManager.HotkeyMode
    var hotkeyMode2: HotkeyManager.HotkeyMode
    var toggleMiniRecorderShortcut: KeyboardShortcuts.Shortcut?
    var toggleMiniRecorderShortcut2: KeyboardShortcuts.Shortcut?

    init(
        id: UUID = UUID(),
        name: String,
        selectedHotkey1: HotkeyManager.HotkeyOption,
        selectedHotkey2: HotkeyManager.HotkeyOption,
        hotkeyMode1: HotkeyManager.HotkeyMode,
        hotkeyMode2: HotkeyManager.HotkeyMode,
        toggleMiniRecorderShortcut: KeyboardShortcuts.Shortcut?,
        toggleMiniRecorderShortcut2: KeyboardShortcuts.Shortcut?
    ) {
        self.id = id
        self.name = name
        self.selectedHotkey1 = selectedHotkey1
        self.selectedHotkey2 = selectedHotkey2
        self.hotkeyMode1 = hotkeyMode1
        self.hotkeyMode2 = hotkeyMode2
        self.toggleMiniRecorderShortcut = toggleMiniRecorderShortcut
        self.toggleMiniRecorderShortcut2 = toggleMiniRecorderShortcut2
    }

    func makeLegacySettings() -> LegacyActivationShortcutSettings {
        LegacyActivationShortcutSettings(
            selectedHotkey1: selectedHotkey1,
            selectedHotkey2: selectedHotkey2,
            hotkeyMode1: hotkeyMode1,
            hotkeyMode2: hotkeyMode2,
            toggleMiniRecorderShortcut: toggleMiniRecorderShortcut,
            toggleMiniRecorderShortcut2: toggleMiniRecorderShortcut2
        )
    }
}

struct LegacyActivationShortcutSettings {
    var selectedHotkey1: HotkeyManager.HotkeyOption
    var selectedHotkey2: HotkeyManager.HotkeyOption
    var hotkeyMode1: HotkeyManager.HotkeyMode
    var hotkeyMode2: HotkeyManager.HotkeyMode
    var toggleMiniRecorderShortcut: KeyboardShortcuts.Shortcut?
    var toggleMiniRecorderShortcut2: KeyboardShortcuts.Shortcut?

    func makeDefaultProfile() -> ActivationShortcutProfile {
        ActivationShortcutProfile(
            name: "Default",
            selectedHotkey1: selectedHotkey1,
            selectedHotkey2: selectedHotkey2,
            hotkeyMode1: hotkeyMode1,
            hotkeyMode2: hotkeyMode2,
            toggleMiniRecorderShortcut: toggleMiniRecorderShortcut,
            toggleMiniRecorderShortcut2: toggleMiniRecorderShortcut2
        )
    }
}

struct ActivationShortcutProfilesState {
    var profiles: [ActivationShortcutProfile]
    var activeProfileID: UUID

    var activeProfile: ActivationShortcutProfile? {
        profiles.first { $0.id == activeProfileID } ?? profiles.first
    }

    init(profiles: [ActivationShortcutProfile], activeProfileID: UUID?) {
        let normalized = Self.normalize(profiles: profiles, activeProfileID: activeProfileID)
        self.profiles = normalized.profiles
        self.activeProfileID = normalized.activeProfileID
    }

    private init(normalizedProfiles: [ActivationShortcutProfile], activeProfileID: UUID) {
        self.profiles = normalizedProfiles
        self.activeProfileID = activeProfileID
    }

    static func makeDefaultState(from legacySettings: LegacyActivationShortcutSettings) -> Self {
        let profile = legacySettings.makeDefaultProfile()
        return Self(normalizedProfiles: [profile], activeProfileID: profile.id)
    }

    static func fromImportedSettings(
        shortcutProfiles: [ActivationShortcutProfile]?,
        activeProfileID: UUID?,
        legacySettings: LegacyActivationShortcutSettings
    ) -> Self {
        if let shortcutProfiles, !shortcutProfiles.isEmpty {
            return Self(profiles: shortcutProfiles, activeProfileID: activeProfileID)
        }

        return makeDefaultState(from: legacySettings)
    }

    static func normalize(profiles: [ActivationShortcutProfile], activeProfileID: UUID?) -> Self {
        var normalizedProfiles = profiles

        if normalizedProfiles.isEmpty {
            let profile = LegacyActivationShortcutSettings(
                selectedHotkey1: .rightCommand,
                selectedHotkey2: .none,
                hotkeyMode1: .hybrid,
                hotkeyMode2: .hybrid,
                toggleMiniRecorderShortcut: nil,
                toggleMiniRecorderShortcut2: nil
            ).makeDefaultProfile()
            return Self(normalizedProfiles: [profile], activeProfileID: profile.id)
        }

        var usedNames = Set<String>()
        var usedIDs = Set<UUID>()

        for index in normalizedProfiles.indices {
            if usedIDs.contains(normalizedProfiles[index].id) {
                normalizedProfiles[index].id = UUID()
            }
            usedIDs.insert(normalizedProfiles[index].id)

            let fallbackName = index == 0 ? "Default" : "Profile \(index + 1)"
            let baseName = normalizedProfiles[index].name
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sanitizedBaseName = baseName.isEmpty ? fallbackName : baseName
            normalizedProfiles[index].name = makeUniqueName(
                base: sanitizedBaseName,
                usedNames: &usedNames
            )
        }

        let resolvedActiveProfileID = normalizedProfiles.contains(where: { $0.id == activeProfileID }) ?
            activeProfileID ?? normalizedProfiles[0].id :
            normalizedProfiles[0].id

        return Self(
            normalizedProfiles: normalizedProfiles,
            activeProfileID: resolvedActiveProfileID
        )
    }

    private static func makeUniqueName(base: String, usedNames: inout Set<String>) -> String {
        var candidate = base
        var suffix = 2

        while usedNames.contains(candidate.lowercased()) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }

        usedNames.insert(candidate.lowercased())
        return candidate
    }
}
