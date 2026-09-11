// mkdir -p build && swiftc VoiceInk/Features/Shortcuts/Coordination/SystemHotKey.swift scripts/check-system-hotkey.swift -o build/check-system-hotkey
import AppKit
import Carbon

@main
struct CheckSystemHotKey {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        var pressedAt: TimeInterval?

        let hotKey = SystemHotKey(keyCode: UInt16(kVK_Space), modifiers: UInt32(optionKey)) { isDown, time in
            print("\(isDown ? "DOWN" : "UP") secureInput=\(IsSecureEventInputEnabled())")
            fflush(stdout)
            if isDown {
                pressedAt = time
            } else if let pressedAt {
                print("PASS: Option-Space delivered both transitions (\(time - pressedAt) seconds).")
                exit(0)
            } else {
                print("FAIL: release arrived without a press.")
                exit(1)
            }
        }
        guard let hotKey else {
            print("FAIL: could not register Option-Space.")
            exit(1)
        }

        print("Press and release Option-Space within 60 seconds. Secure Input: \(IsSecureEventInputEnabled()).")
        fflush(stdout)
        Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in
            print("FAIL: no complete shortcut press received before the timeout.")
            exit(1)
        }
        withExtendedLifetime(hotKey) {
            application.run()
        }
    }
}
