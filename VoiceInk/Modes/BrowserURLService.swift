import Foundation
import AppKit
import os

enum BrowserType {
    case safari
    case arc
    case chrome
    case edge
    case brave
    case opera
    case vivaldi
    case orion
    case yandex
    
    var scriptName: String {
        switch self {
        case .safari: return "safariURL"
        case .arc: return "arcURL"
        case .chrome: return "chromeURL"
        case .edge: return "edgeURL"
        case .brave: return "braveURL"
        case .opera: return "operaURL"
        case .vivaldi: return "vivaldiURL"
        case .orion: return "orionURL"
        case .yandex: return "yandexURL"
        }
    }
    
    var bundleIdentifier: String {
        switch self {
        case .safari: return "com.apple.Safari"
        case .arc: return "company.thebrowser.Browser"
        case .chrome: return "com.google.Chrome"
        case .edge: return "com.microsoft.edgemac"
        case .brave: return "com.brave.Browser"
        case .opera: return "com.operasoftware.Opera"
        case .vivaldi: return "com.vivaldi.Vivaldi"
        case .orion: return "com.kagi.kagimacOS"
        case .yandex: return "ru.yandex.desktop.yandex-browser"
        }
    }
    
    var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .arc: return "Arc"
        case .chrome: return "Google Chrome"
        case .edge: return "Microsoft Edge"
        case .brave: return "Brave"
        case .opera: return "Opera"
        case .vivaldi: return "Vivaldi"
        case .orion: return "Orion"
        case .yandex: return "Yandex Browser"
        }
    }
    
    static var allCases: [BrowserType] {
        [.safari, .arc, .chrome, .edge, .brave, .opera, .vivaldi, .orion, .yandex]
    }
    
    static var installedBrowsers: [BrowserType] {
        allCases.filter { browser in
            let workspace = NSWorkspace.shared
            return workspace.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) != nil
        }
    }
}

enum BrowserURLError: Error {
    case scriptNotFound
    case executionFailed
    case executionTimedOut
    case browserNotRunning
    case noActiveWindow
    case noActiveTab
}

class BrowserURLService {
    static let shared = BrowserURLService()
    
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "browser.applescript"
    )
    private let scriptTimeout: TimeInterval = 1.5
    
    private init() {}
    
    func getCurrentURL(from browser: BrowserType) async throws -> String {
        guard let scriptURL = Bundle.main.url(forResource: browser.scriptName, withExtension: "scpt") else {
            logger.error("❌ AppleScript file not found: \(browser.scriptName, privacy: .public).scpt")
            throw BrowserURLError.scriptNotFound
        }
        
        logger.debug("🔍 Attempting to execute AppleScript for \(browser.displayName, privacy: .public)")
        
        // Check if browser is running
        if !isRunning(browser) {
            logger.error("❌ Browser not running: \(browser.displayName, privacy: .public)")
            throw BrowserURLError.browserNotRunning
        }
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = [scriptURL.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            logger.debug("▶️ Executing AppleScript for \(browser.displayName, privacy: .public)")
            try task.run()
            try await waitUntilExit(task, browser: browser)
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if output.isEmpty {
                    logger.error("❌ Empty output from AppleScript for \(browser.displayName, privacy: .public)")
                    throw BrowserURLError.noActiveTab
                }
                
                // Check if output contains error messages
                if output.lowercased().contains("error") {
                    logger.error("❌ AppleScript error for \(browser.displayName, privacy: .public): \(output, privacy: .public)")
                    throw BrowserURLError.executionFailed
                }
                
                logger.debug("✅ Successfully retrieved URL from \(browser.displayName, privacy: .public): \(output, privacy: .public)")
                return output
            } else {
                logger.error("❌ Failed to decode output from AppleScript for \(browser.displayName, privacy: .public)")
                throw BrowserURLError.executionFailed
            }
        } catch let error as BrowserURLError {
            throw error
        } catch is CancellationError {
            if task.isRunning {
                task.terminate()
            }
            throw CancellationError()
        } catch {
            logger.error("❌ AppleScript execution failed for \(browser.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw BrowserURLError.executionFailed
        }
    }

    private func waitUntilExit(_ task: Process, browser: BrowserType) async throws {
        let timeoutDate = Date().addingTimeInterval(scriptTimeout)
        while task.isRunning {
            if Date() >= timeoutDate {
                task.terminate()
                logger.error("❌ AppleScript timed out for \(browser.displayName, privacy: .public)")
                throw BrowserURLError.executionTimedOut
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    
    func isRunning(_ browser: BrowserType) -> Bool {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        let isRunning = runningApps.contains { $0.bundleIdentifier == browser.bundleIdentifier }
        logger.debug("\(browser.displayName, privacy: .public) running status: \(isRunning, privacy: .public)")
        return isRunning
    }
} 
