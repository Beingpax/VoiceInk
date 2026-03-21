import AppKit
import KeyboardShortcuts
import Testing
@testable import VoiceInk

struct VoiceInkTests {

    @Test
    func legacyHotkeyMigrationCreatesDefaultProfile() {
        let legacyShortcut = KeyboardShortcuts.Shortcut(.r, modifiers: .command)

        let state = ActivationShortcutProfilesState.makeDefaultState(
            from: LegacyActivationShortcutSettings(
                selectedHotkey1: .rightOption,
                selectedHotkey2: .rightCommand,
                hotkeyMode1: .pushToTalk,
                hotkeyMode2: .toggle,
                toggleMiniRecorderShortcut: legacyShortcut,
                toggleMiniRecorderShortcut2: nil
            )
        )

        #expect(state.profiles.count == 1)

        guard let activeProfile = state.activeProfile else {
            Issue.record("Expected an active profile after legacy migration")
            return
        }

        #expect(activeProfile.name == "Default")
        #expect(activeProfile.selectedHotkey1 == .rightOption)
        #expect(activeProfile.selectedHotkey2 == .rightCommand)
        #expect(activeProfile.hotkeyMode1 == .pushToTalk)
        #expect(activeProfile.hotkeyMode2 == .toggle)
        #expect(activeProfile.toggleMiniRecorderShortcut?.key == legacyShortcut.key)
        #expect(activeProfile.toggleMiniRecorderShortcut?.modifiers == legacyShortcut.modifiers)
        #expect(state.activeProfileID == activeProfile.id)
    }

    @Test
    func profileNormalizationDeduplicatesIDsAndNames() {
        let duplicatedID = UUID()
        let profiles = [
            ActivationShortcutProfile(
                id: duplicatedID,
                name: " Home ",
                selectedHotkey1: .rightCommand,
                selectedHotkey2: .none,
                hotkeyMode1: .hybrid,
                hotkeyMode2: .hybrid,
                toggleMiniRecorderShortcut: nil,
                toggleMiniRecorderShortcut2: nil
            ),
            ActivationShortcutProfile(
                id: duplicatedID,
                name: "Home",
                selectedHotkey1: .rightOption,
                selectedHotkey2: .none,
                hotkeyMode1: .toggle,
                hotkeyMode2: .hybrid,
                toggleMiniRecorderShortcut: nil,
                toggleMiniRecorderShortcut2: nil
            )
        ]

        let state = ActivationShortcutProfilesState(profiles: profiles, activeProfileID: UUID())

        #expect(state.profiles.count == 2)
        #expect(state.profiles[0].name == "Home")
        #expect(state.profiles[1].name == "Home 2")
        #expect(state.profiles[0].id != state.profiles[1].id)
        #expect(state.activeProfileID == state.profiles[0].id)
    }

    @Test
    func activationShortcutProfileRoundTripsThroughCodable() throws {
        let primaryShortcut = KeyboardShortcuts.Shortcut(.m, modifiers: [.command, .shift])
        let secondaryShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: .option)
        let profile = ActivationShortcutProfile(
            name: "Laptop",
            selectedHotkey1: .custom,
            selectedHotkey2: .custom,
            hotkeyMode1: .hybrid,
            hotkeyMode2: .pushToTalk,
            toggleMiniRecorderShortcut: primaryShortcut,
            toggleMiniRecorderShortcut2: secondaryShortcut
        )

        let data = try JSONEncoder().encode([profile])
        let decodedProfiles = try JSONDecoder().decode([ActivationShortcutProfile].self, from: data)

        #expect(decodedProfiles.count == 1)

        guard let decodedProfile = decodedProfiles.first else {
            Issue.record("Expected one decoded shortcut profile")
            return
        }

        #expect(decodedProfile.name == profile.name)
        #expect(decodedProfile.selectedHotkey1 == .custom)
        #expect(decodedProfile.selectedHotkey2 == .custom)
        #expect(decodedProfile.hotkeyMode2 == .pushToTalk)
        #expect(decodedProfile.toggleMiniRecorderShortcut?.key == primaryShortcut.key)
        #expect(decodedProfile.toggleMiniRecorderShortcut?.modifiers == primaryShortcut.modifiers)
        #expect(decodedProfile.toggleMiniRecorderShortcut2?.key == secondaryShortcut.key)
        #expect(decodedProfile.toggleMiniRecorderShortcut2?.modifiers == secondaryShortcut.modifiers)
    }

    @Test
    func importedSettingsPreferProfilesAndFallbackToLegacy() {
        let legacySettings = LegacyActivationShortcutSettings(
            selectedHotkey1: .rightOption,
            selectedHotkey2: .none,
            hotkeyMode1: .toggle,
            hotkeyMode2: .hybrid,
            toggleMiniRecorderShortcut: nil,
            toggleMiniRecorderShortcut2: nil
        )

        let importedProfile = ActivationShortcutProfile(
            name: "Work Wired",
            selectedHotkey1: .rightCommand,
            selectedHotkey2: .none,
            hotkeyMode1: .hybrid,
            hotkeyMode2: .hybrid,
            toggleMiniRecorderShortcut: nil,
            toggleMiniRecorderShortcut2: nil
        )

        let preferredState = ActivationShortcutProfilesState.fromImportedSettings(
            shortcutProfiles: [importedProfile],
            activeProfileID: importedProfile.id,
            legacySettings: legacySettings
        )

        let fallbackState = ActivationShortcutProfilesState.fromImportedSettings(
            shortcutProfiles: nil,
            activeProfileID: nil,
            legacySettings: legacySettings
        )

        #expect(preferredState.activeProfile?.name == "Work Wired")
        #expect(preferredState.activeProfile?.selectedHotkey1 == .rightCommand)
        #expect(fallbackState.activeProfile?.name == "Default")
        #expect(fallbackState.activeProfile?.selectedHotkey1 == .rightOption)
        #expect(fallbackState.activeProfile?.hotkeyMode1 == .toggle)
    }
}
