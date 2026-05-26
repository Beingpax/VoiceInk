import Foundation
import AppKit

class AutomationActionService {
    static let shared = AutomationActionService()
    
    private init() {}
    
    /// Parses the text for automation commands. If any command is matched, executes it.
    /// Returns a tuple: (shouldPaste: Bool, cleanedText: String)
    func processActions(in text: String) -> (shouldPaste: Bool, cleanedText: String) {
        let lines = text.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        var didExecuteAction = false
        var shouldPasteText = true
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.hasPrefix("/search google ") {
                let query = String(trimmedLine.dropFirst("/search google ".count))
                searchGoogle(query)
                didExecuteAction = true
                shouldPasteText = false
            } else if trimmedLine.hasPrefix("/search perplexity ") {
                let query = String(trimmedLine.dropFirst("/search perplexity ".count))
                searchPerplexity(query)
                didExecuteAction = true
                shouldPasteText = false
            } else if trimmedLine.hasPrefix("/search youtube ") {
                let query = String(trimmedLine.dropFirst("/search youtube ".count))
                searchYoutube(query)
                didExecuteAction = true
                shouldPasteText = false
            } else if trimmedLine.hasPrefix("/open ") {
                let urlString = String(trimmedLine.dropFirst("/open ".count))
                openURL(urlString)
                didExecuteAction = true
                shouldPasteText = false
            } else if trimmedLine.hasPrefix("/press ") {
                let keysString = String(trimmedLine.dropFirst("/press ".count))
                pressKeys(keysString)
                didExecuteAction = true
                shouldPasteText = false
            } else {
                cleanedLines.append(line)
            }
        }
        
        let cleanedText = cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (shouldPaste: shouldPasteText && !didExecuteAction, cleanedText: cleanedText)
    }
    
    private func searchGoogle(_ query: String) {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encodedQuery)") else { return }
        NSWorkspace.shared.open(url)
    }
    
    private func searchPerplexity(_ query: String) {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.perplexity.ai/search?q=\(encodedQuery)") else { return }
        NSWorkspace.shared.open(url)
    }
    
    private func searchYoutube(_ query: String) {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.youtube.com/results?search_query=\(encodedQuery)") else { return }
        NSWorkspace.shared.open(url)
    }
    
    private func openURL(_ urlString: String) {
        var formattedUrlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !formattedUrlString.hasPrefix("http://") && !formattedUrlString.hasPrefix("https://") {
            formattedUrlString = "https://" + formattedUrlString
        }
        if let url = URL(string: formattedUrlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func pressKeys(_ keysString: String) {
        let trimmed = keysString.lowercased().trimmingCharacters(in: .whitespaces)
        var appleScript = ""
        
        if trimmed == "enter" || trimmed == "return" {
            appleScript = "tell application \"System Events\" to keystroke return"
        } else if trimmed == "tab" {
            appleScript = "tell application \"System Events\" to keystroke tab"
        } else if trimmed == "space" {
            appleScript = "tell application \"System Events\" to keystroke space"
        } else if trimmed == "escape" || trimmed == "esc" {
            appleScript = "tell application \"System Events\" to key code 53"
        } else if trimmed.contains("+") {
            let parts = trimmed.components(separatedBy: "+")
            let key = parts.last ?? ""
            let modifiers = parts.dropLast()
            
            var modifierString = ""
            for mod in modifiers {
                let m = mod.trimmingCharacters(in: .whitespaces)
                if m == "cmd" || m == "command" {
                    modifierString += "command down, "
                } else if m == "shift" {
                    modifierString += "shift down, "
                } else if m == "option" || m == "opt" || m == "alt" {
                    modifierString += "option down, "
                } else if m == "ctrl" || m == "control" {
                    modifierString += "control down, "
                }
            }
            if modifierString.hasSuffix(", ") {
                modifierString = String(modifierString.dropLast(2))
            }
            
            if !key.isEmpty {
                if modifierString.isEmpty {
                    appleScript = "tell application \"System Events\" to keystroke \"\(key)\""
                } else {
                    appleScript = "tell application \"System Events\" to keystroke \"\(key)\" using {\(modifierString)}"
                }
            }
        } else {
            appleScript = "tell application \"System Events\" to keystroke \"\(trimmed)\""
        }
        
        if !appleScript.isEmpty {
            let script = NSAppleScript(source: appleScript)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
        }
    }
}
