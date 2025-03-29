import Foundation
import AppKit
import OSLog

class CursorPaster {
    private static let pasteCompletionDelay: TimeInterval = 0.3
    private static let logger = Logger(subsystem: "com.voiceink", category: "CursorPaster")
    
    static func pasteAtCursor(_ text: String) {
        guard AXIsProcessTrusted() else {
            print("Accessibility permissions not granted. Cannot paste at cursor.")
            return
        }
        
        // Save the current pasteboard contents
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        
        // Set the new text to paste
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Use the preferred paste method based on user settings
        if UserDefaults.standard.useAppleScriptPaste {
            pasteUsingAppleScript()
        } else {
            pasteUsingCommandV()
        }
        
        // Restore the original pasteboard content
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + pasteCompletionDelay) {
            pasteboard.clearContents()
            if let oldContents = oldContents {
                pasteboard.setString(oldContents, forType: .string)
            }
        }
    }
    
    private static func pasteUsingAppleScript() -> Bool {
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if error != nil {
                print("AppleScript paste failed: \(error?.description ?? "Unknown error")")
                logger.notice("AppleScript paste failed with error: \(error?.description ?? "Unknown error")")
                return false
            }
            logger.notice("AppleScript paste completed successfully")
            return true
        }
        return false
    }
    
    private static func pasteUsingCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        logger.notice("Command+V paste completed")
    }
}

