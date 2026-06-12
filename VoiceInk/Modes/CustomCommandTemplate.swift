import Foundation

enum CustomCommandTemplate: String, CaseIterable, Identifiable {
    case pasteAndPressTab
    case appendToJournal
    case searchWeb

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pasteAndPressTab:
            return String(localized: "Paste and Press Tab")
        case .appendToJournal:
            return String(localized: "Append to Journal")
        case .searchWeb:
            return String(localized: "Search Web")
        }
    }

    var command: String {
        switch self {
        case .pasteAndPressTab:
            return """
            printf "%s" "$VOICEINK_TRANSCRIPT" | pbcopy
            osascript <<'APPLESCRIPT'
            tell application "System Events"
                keystroke "v" using command down
                delay 1
                key code 48
            end tell
            APPLESCRIPT
            """
        case .appendToJournal:
            return """
            mkdir -p "$HOME/Documents/VoiceInk"
            journal="$HOME/Documents/VoiceInk/journal.md"
            timestamp=$(date "+%Y-%m-%d %H:%M")
            printf -- "- **%s** %s\\n" "$timestamp" "$VOICEINK_TRANSCRIPT" >> "$journal"
            """
        case .searchWeb:
            return """
            query=$(printf "%s" "$VOICEINK_TRANSCRIPT" | LC_ALL=C od -An -tx1 -v | tr -d ' \\n' | sed 's/../%&/g')
            open "https://www.google.com/search?q=$query"
            """
        }
    }
}
