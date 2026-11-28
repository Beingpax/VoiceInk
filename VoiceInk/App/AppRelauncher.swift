import AppKit

/// Quits VoiceInk and opens it again.
enum AppRelauncher {
    @MainActor
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        // Waits up to 10 seconds for this process to exit, then reopens the app. If quitting
        // was cancelled, it gives up instead of reopening VoiceInk later.
        let script = """
            for _ in $(seq 1 50); do
              kill -0 \(pid) 2>/dev/null || { /usr/bin/open "$0"; exit 0; }
              sleep 0.2
            done
            """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script, Bundle.main.bundleURL.path]
        do {
            try helper.run()
        } catch {
            return
        }
        NSApplication.shared.terminate(nil)
    }
}
