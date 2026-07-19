import AppKit
import Testing

@testable import VoiceInk

// ShortcutValidator itself isn't covered here — its only accessible entry
// point (`validationError(for:action:)`) reaches through to `ModeManager.shared`
// and `ShortcutStore`, both live global state, so it isn't safely unit-testable
// without touching real app state. `Shortcut`'s own display logic has no such
// dependency and is covered below.
struct ShortcutTests {

    @Test func keyShortcutDisplaysModifiersThenKeyName() {
        // The resolved key *character* (Shortcut.keyName -> characterForCurrentKeyboardLayout)
        // depends on the live system keyboard layout via TISCopyCurrentKeyboardInputSource,
        // which isn't controllable in CI — asserting displayTokens.last == "A" for keyCode
        // 0x00 flaked on GitHub's runner because that keyCode didn't resolve to "A" there.
        // What displayTokens actually guarantees by construction
        // (modifierFlags.shortcutDisplayTokens + [keyName]) is structural: modifier tokens
        // precede a non-empty key name, regardless of which character it resolves to.
        let shortcut = Shortcut.key(keyCode: 0x00, modifierFlags: [.command])

        #expect(shortcut.displayTokens.count == 2)
        #expect(shortcut.displayTokens.first == "⌘")
        #expect(!(shortcut.displayTokens.last?.isEmpty ?? true))
    }

    @Test func equalShortcutsCompareEqual() {
        let a = Shortcut.key(keyCode: 0x00, modifierFlags: [.command])
        let b = Shortcut.key(keyCode: 0x00, modifierFlags: [.command])
        #expect(a == b)
    }

    @Test func differentKeyCodesAreNotEqual() {
        let a = Shortcut.key(keyCode: 0x00, modifierFlags: [.command])
        let b = Shortcut.key(keyCode: 0x01, modifierFlags: [.command])
        #expect(a != b)
    }

    @Test func modifierOnlyShortcutIsFlaggedAsSuch() {
        let shortcut = Shortcut.modifierOnly(keyCode: nil, modifierFlags: [.option])
        #expect(shortcut.isModifierOnly == true)
    }

    @Test func keyShortcutIsNotFlaggedAsModifierOnly() {
        let shortcut = Shortcut.key(keyCode: 0x00, modifierFlags: [.command])
        #expect(shortcut.isModifierOnly == false)
    }
}
