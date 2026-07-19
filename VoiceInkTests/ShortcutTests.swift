import AppKit
import Carbon.HIToolbox
import Testing

@testable import VoiceInk

// ShortcutValidator itself isn't covered here — its only accessible entry
// point (`validationError(for:action:)`) reaches through to `ModeManager.shared`
// and `ShortcutStore`, both live global state, so it isn't safely unit-testable
// without touching real app state. `Shortcut`'s own display logic has no such
// dependency and is covered below.
struct ShortcutTests {

    @Test func keyShortcutDisplaysModifiersThenKeyName() {
        // keyCode 0x00 ('A' on US QWERTY) isn't in Shortcut.specialKeyNames, so resolving
        // it calls Shortcut.keyName -> characterForCurrentKeyboardLayout ->
        // TISCopyCurrentKeyboardInputSource, a Carbon HIToolbox call that reads the live
        // system keyboard layout. Two failures in a row on GitHub's headless CI runner
        // traced to that exact call: the first attempt just asserted the wrong resolved
        // character (fixed, but still called it); the second showed the call itself
        // hanging for ~40s before the whole test run gave up. kVK_Return *is* a special
        // key name (Shortcut.specialKeyNames), so keyName short-circuits before ever
        // reaching the Carbon call — this test now covers the same displayTokens ordering
        // guarantee without touching that code path at all.
        let shortcut = Shortcut.key(keyCode: UInt16(kVK_Return), modifierFlags: [.command])

        #expect(shortcut.displayTokens.count == 2)
        #expect(shortcut.displayTokens.first == "⌘")
        #expect(shortcut.displayTokens.last == "Return")
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
