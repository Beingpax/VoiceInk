import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Uses physical key events for receivers that discard Unicode event payloads.
/// The host and remote keyboard layouts must match. Posting is not an
/// acknowledgement that the remote editor accepted the text.
@MainActor
enum RemoteTextTyper {
    enum Result {
        case posted
        case notPosted
        case unsupportedCharacters
        case partiallyPosted
    }

    private struct KeyStroke {
        let code: CGKeyCode
        let shift: Bool
    }

    // Matches the pacing used by the remote typing implementation in PR #701.
    private static let interKeyDelayNanoseconds: UInt64 = 5_000_000
    private static let interferingModifiers: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift, .maskAlphaShift,
    ]

    static func type(_ text: String, sendKey: FinishAndSendKey) async -> Result {
        guard !Task.isCancelled, AXIsProcessTrusted(),
            let source = CGEventSource(stateID: .privateState),
            let map = keyboardMap(),
            let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else { return .notPosted }

        // Preflight the whole transcript. Falling back to a Unicode payload on
        // an unmapped key produces spaces or incorrect letters in some viewers.
        var keys: [KeyStroke] = []
        for character in DirectTextTyper.normalizedText(text) {
            switch character {
            case "\n":
                keys.append(KeyStroke(code: CGKeyCode(kVK_Return), shift: sendKey == .enter))
            case "\t":
                keys.append(KeyStroke(code: CGKeyCode(kVK_Tab), shift: false))
            default:
                guard let key = map[character] else { return .unsupportedCharacters }
                keys.append(key)
            }
        }
        guard !keys.isEmpty else { return .notPosted }

        var postedKeys = 0
        for key in keys {
            // Physical typing must not become shortcuts if the recording hotkey
            // is still held. Also stop if the user switches applications.
            guard !Task.isCancelled,
                NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID,
                CGEventSource.flagsState(.hidSystemState).intersection(interferingModifiers).isEmpty,
                let down = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: false)
            else { return postedKeys == 0 ? .notPosted : .partiallyPosted }

            let shiftDown = key.shift
                ? CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Shift), keyDown: true) : nil
            let shiftUp = key.shift
                ? CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Shift), keyDown: false) : nil
            guard !key.shift || (shiftDown != nil && shiftUp != nil) else {
                return postedKeys == 0 ? .notPosted : .partiallyPosted
            }

            // Real Shift transitions are needed by remote clients that ignore
            // modifier flags on a character event (the fix verified in PR #758).
            // Allocate all events first, and never suspend with Shift held.
            shiftDown?.flags = .maskShift
            shiftDown?.post(tap: .cghidEventTap)
            down.flags = key.shift ? .maskShift : []
            up.flags = key.shift ? .maskShift : []
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            shiftUp?.flags = []
            shiftUp?.post(tap: .cghidEventTap)
            postedKeys += 1

            if postedKeys < keys.count {
                do {
                    try await Task.sleep(nanoseconds: interKeyDelayNanoseconds)
                } catch {
                    return .partiallyPosted
                }
            }
        }
        return .posted
    }

    private static func keyboardMap() -> [Character: KeyStroke]? {
        guard let input = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let dataRef = TISGetInputSourceProperty(input, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = unsafeBitCast(dataRef, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return nil }

        var map: [Character: KeyStroke] = [:]
        // Prefer unmodified keys over shifted equivalents. Option, dead-key
        // sequences, and input methods cannot be reproduced by this transport.
        for shift in [false, true] {
            for code in UInt16(0)..<UInt16(128) {
                var deadKeyState: UInt32 = 0
                var characters = [UniChar](repeating: 0, count: 8)
                var length = 0
                let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
                    UCKeyTranslate(
                        layout, code, UInt16(kUCKeyActionDown),
                        shift ? UInt32(shiftKey >> 8) : 0,
                        UInt32(LMGetKbdType()), 0, &deadKeyState,
                        characters.count, &length, &characters
                    )
                }
                guard status == noErr, deadKeyState == 0, length > 0 else { continue }
                let result = String(utf16CodeUnits: characters, count: length)
                guard result.count == 1, let character = result.first,
                    !character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                    map[character] == nil
                else { continue }
                map[character] = KeyStroke(code: CGKeyCode(code), shift: shift)
            }
        }
        return map
    }
}
