import AppIntents
import Foundation

struct AppShortcuts : AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
            AppShortcut(
                intent: ToggleMiniRecorderIntent(),
                phrases: [
                    "Toggle \(.applicationName) recorder",
                    "Start \(.applicationName) recording",
                    "Stop \(.applicationName) recording",
                    "Toggle recorder in \(.applicationName)",
                    "Start recording in \(.applicationName)",
                    "Stop recording in \(.applicationName)"
                ],
                shortTitle: "Toggle Recorder",
                systemImageName: "mic.circle"
            )
            
            AppShortcut(
                intent: DismissMiniRecorderIntent(),
                phrases: [
                    "Dismiss \(.applicationName) recorder",
                    "Cancel \(.applicationName) recording",
                    "Close \(.applicationName) recorder",
                    "Hide \(.applicationName) recorder"
                ],
                shortTitle: "Dismiss Recorder",
                systemImageName: "xmark.circle"
            )
    }
}
