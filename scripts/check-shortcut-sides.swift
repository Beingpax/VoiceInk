// Checks left/right modifier matching in Shortcut.swift without building the app.
// Run from the repo root:
//   xcrun swiftc -swift-version 5 -parse-as-library -o /tmp/check-shortcut-sides \
//     scripts/check-shortcut-sides.swift VoiceInk/Features/Shortcuts/Models/Shortcut.swift \
//     && /tmp/check-shortcut-sides
// Every event below carries explicit side bits, so results do not depend on keys held during the run.

import AppKit
import Carbon.HIToolbox
import IOKit.hidsystem

// Stub for the one app type Shortcut.swift references.
struct LegacyKeyboardShortcut: Codable {
    let carbonKeyCode: Int
    let carbonModifiers: Int
}

@main
enum ShortcutSideChecks {
    static let lCmd = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELCMDKEYMASK))
    static let rCmd = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERCMDKEYMASK))
    static let lCtl = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELCTLKEYMASK))
    static let lAlt = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELALTKEYMASK))
    static let rAlt = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERALTKEYMASK))
    static let space = UInt16(kVK_Space)
    static let kKey = UInt16(kVK_ANSI_K)

    static var failures = 0

    static func check(_ name: String, _ condition: Bool) {
        print("\(condition ? "PASS" : "FAIL")  \(name)")
        if !condition { failures += 1 }
    }

    static func main() {
        // Key + sided modifier
        let leftCmdSpace = Shortcut.key(keyCode: space, modifierFlags: [.command, lCmd])
        check("L⌘Space matches L⌘ event", leftCmdSpace.matchesKeyEvent(keyCode: space, modifierFlags: [.command, lCmd]))
        check("L⌘Space rejects R⌘ event", !leftCmdSpace.matchesKeyEvent(keyCode: space, modifierFlags: [.command, rCmd]))
        check("L⌘Space rejects both-⌘ event", !leftCmdSpace.matchesKeyEvent(keyCode: space, modifierFlags: [.command, lCmd, rCmd]))
        check("L⌘Space rejects extra ⌥", !leftCmdSpace.matchesKeyEvent(keyCode: space, modifierFlags: [.command, .option, lCmd, lAlt]))
        check("L⌘Space display", leftCmdSpace.displayString.hasPrefix("Left ⌘ + "))

        // Side-agnostic key shortcut still matches either side
        let anyCmdSpace = Shortcut.key(keyCode: space, modifierFlags: [.command])
        check("⌘Space matches L⌘", anyCmdSpace.matchesKeyEvent(keyCode: space, modifierFlags: [.command, lCmd]))
        check("⌘Space matches R⌘", anyCmdSpace.matchesKeyEvent(keyCode: space, modifierFlags: [.command, rCmd]))
        check("⌘Space display unchanged", anyCmdSpace.displayString.hasPrefix("⌘ + "))

        // Side bits without their generic modifier are dropped
        let stray = Shortcut.key(keyCode: space, modifierFlags: [.option, lCmd])
        check("stray side bit dropped", stray.modifierFlags == [.option])

        // Conflicts
        let leftCmdK = Shortcut.key(keyCode: kKey, modifierFlags: [.command, lCmd])
        let rightCmdK = Shortcut.key(keyCode: kKey, modifierFlags: [.command, rCmd])
        let anyCmdK = Shortcut.key(keyCode: kKey, modifierFlags: [.command])
        check("L⌘K vs R⌘K no conflict", !leftCmdK.conflicts(with: rightCmdK))
        check("⌘K vs L⌘K conflict", anyCmdK.conflicts(with: leftCmdK) && leftCmdK.conflicts(with: anyCmdK))
        check("L⌘K vs L⌘K conflict", leftCmdK.conflicts(with: leftCmdK))

        // Held / release for sided key shortcuts
        check("L⌘Space held with L⌘", leftCmdSpace.modifiersStillHeld(in: [.command, lCmd]))
        check("L⌘Space not held with R⌘", !leftCmdSpace.modifiersStillHeld(in: [.command, rCmd]))
        check("L⌘Space not held with none", !leftCmdSpace.modifiersStillHeld(in: []))
        check("⌘Space held with R⌘", anyCmdSpace.modifiersStillHeld(in: [.command, rCmd]))

        // Multi-modifier-only chord with sides
        let chord = Shortcut.modifierOnly(keyCode: nil, modifierFlags: [.control, .option, lCtl, rAlt])
        check("L⌃R⌥ matches", chord.matchesModifierEvent(keyCode: UInt16(kVK_RightOption), modifierFlags: [.control, .option, lCtl, rAlt]))
        check("L⌃R⌥ rejects L⌃L⌥", !chord.matchesModifierEvent(keyCode: UInt16(kVK_Option), modifierFlags: [.control, .option, lCtl, lAlt]))
        check("L⌃R⌥ releases when R⌥ up", chord.shouldReleaseModifierEvent(keyCode: UInt16(kVK_RightOption), modifierFlags: [.control, lCtl]))
        check("L⌃R⌥ stays when both held", !chord.shouldReleaseModifierEvent(keyCode: UInt16(kVK_Control), modifierFlags: [.control, .option, lCtl, rAlt]))
        check("L⌃R⌥ display", chord.displayString == "Left ⌃ + Right ⌥")

        // Single side-specific modifier (upstream semantics preserved)
        let recordedRightCmd = Shortcut.modifierOnly(keyCode: UInt16(kVK_RightCommand), modifierFlags: [.command, rCmd])
        check("recorded Right ⌘ equals default .rightCommand", recordedRightCmd == Shortcut.rightCommand)
        check("Right ⌘ matches", Shortcut.rightCommand.matchesModifierEvent(keyCode: UInt16(kVK_RightCommand), modifierFlags: [.command, rCmd]))
        check("Right ⌘ rejects when only L⌘ down", !Shortcut.rightCommand.matchesModifierEvent(keyCode: UInt16(kVK_RightCommand), modifierFlags: [.command, lCmd]))
        check("Right ⌘ releases when R⌘ up but L⌘ held", Shortcut.rightCommand.shouldReleaseModifierEvent(keyCode: UInt16(kVK_RightCommand), modifierFlags: [.command, lCmd]))
        check("Right ⌘ display", Shortcut.rightCommand.displayString == "Right ⌘")

        // Mouse with sided modifier
        let mouse = Shortcut.mouseButton(buttonNumber: 3, modifierFlags: [.option, rAlt])
        check("R⌥+Mouse matches", mouse.matchesMouseEvent(buttonNumber: 3, modifierFlags: [.option, rAlt]))
        check("R⌥+Mouse rejects L⌥", !mouse.matchesMouseEvent(buttonNumber: 3, modifierFlags: [.option, lAlt]))

        // Persistence round trip and old side-agnostic data
        let data = try! JSONEncoder().encode(leftCmdSpace)
        let decoded = try! JSONDecoder().decode(Shortcut.self, from: data)
        check("Codable keeps sides", decoded == leftCmdSpace && decoded.modifierFlags.contains(lCmd))
        let oldData = try! JSONEncoder().encode(anyCmdSpace)
        check("old side-agnostic data decodes", (try? JSONDecoder().decode(Shortcut.self, from: oldData)) == anyCmdSpace)

        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
