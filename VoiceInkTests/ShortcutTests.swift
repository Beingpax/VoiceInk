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
        let shortcut = Shortcut.key(keyCode: 0x00, modifierFlags: [.command])  // 'A'
        #expect(shortcut.displayTokens.last == "A")
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
