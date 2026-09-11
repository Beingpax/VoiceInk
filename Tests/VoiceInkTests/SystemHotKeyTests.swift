import AppKit
import Carbon
import Testing
@testable import VoiceInk

@Suite(.serialized)
struct SystemHotKeyTests {
    @Test func optionSpaceUsesSystemRegistration() {
        let shortcut = Shortcut.key(keyCode: UInt16(kVK_Space), modifierFlags: [.option])

        #expect(shortcut.systemHotKeyModifiers == UInt32(optionKey))
    }

    @Test func functionKeyNormalizesItsImplicitFnFlag() {
        let shortcut = Shortcut.key(keyCode: UInt16(kVK_F5), modifierFlags: [.function, .control])

        #expect(shortcut.systemHotKeyModifiers == UInt32(controlKey))
    }

    @Test func unsupportedInputsKeepTheirEventTapRoute() {
        let shortcuts: [Shortcut] = [
            .key(keyCode: UInt16(kVK_Space), modifierFlags: [.function]),
            .rightCommand,
            .mouseButton(buttonNumber: 3, modifierFlags: [.option]),
        ]

        #expect(shortcuts.allSatisfy { $0.systemHotKeyModifiers == nil })
    }

    @Test func unmodifiedEscapeCanCancelTheRecorder() {
        let shortcut = Shortcut.key(keyCode: UInt16(kVK_Escape), modifierFlags: [])

        #expect(shortcut.systemHotKeyModifiers == 0)
    }

    @Test @MainActor func releasingARegistrationAllowsTheShortcutToBeReused() {
        let keyCode = UInt16(kVK_F19)
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        var first = SystemHotKey(keyCode: keyCode, modifiers: modifiers) { _, _ in }
        #expect(first != nil)
        withExtendedLifetime(first) {
            let duplicate = SystemHotKey(keyCode: keyCode, modifiers: modifiers) { _, _ in }
            #expect(duplicate == nil)
        }

        first = nil
        let replacement = SystemHotKey(keyCode: keyCode, modifiers: modifiers) { _, _ in }

        #expect(replacement != nil)
        withExtendedLifetime(replacement) {}
    }
}
