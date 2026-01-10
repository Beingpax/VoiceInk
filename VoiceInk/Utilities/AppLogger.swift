import Foundation
import OSLog

/// Centralized logging system for \(AppBrand.communityName)
///
/// Provides structured, categorized logging with consistent formatting across the application.
/// Uses OSLog for performance and integration with macOS Console.app.
///
/// ## Usage
/// ```swift
/// AppLogger.transcription.info("Starting transcription for \(audioURL.lastPathComponent)")
/// AppLogger.audio.error("Failed to configure audio device: \(error)")
/// ```
struct AppLogger {
    private init() {}
    
    // MARK: - Subsystem
    
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.tmm22.voicelinkcommunity"
    
    // MARK: - Category Loggers
    
    /// Logger for transcription operations
    ///
    /// Use for:
    /// - Starting/stopping transcription
    /// - Model loading/unloading
    /// - Transcription results
    /// - Transcription errors
    static let transcription = Logger(subsystem: subsystem, category: "Transcription")
    
    /// Logger for audio operations
    ///
    /// Use for:
    /// - Audio device configuration
    /// - Recording start/stop
    /// - Audio level monitoring
    /// - Audio file operations
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    
    /// Logger for Power Mode operations
    ///
    /// Use for:
    /// - Power Mode activation/deactivation
    /// - Configuration application
    /// - App/URL detection
    /// - Session management
    static let powerMode = Logger(subsystem: subsystem, category: "PowerMode")
    
    /// Logger for AI enhancement operations
    ///
    /// Use for:
    /// - AI provider communication
    /// - Enhancement requests/responses
    /// - Prompt processing
    /// - Context capture
    static let ai = Logger(subsystem: subsystem, category: "AI")
    
    /// Logger for UI operations
    ///
    /// Use for:
    /// - Window management
    /// - View lifecycle
    /// - User interactions
    /// - UI state changes
    static let ui = Logger(subsystem: subsystem, category: "UI")
    
    /// Logger for network operations
    ///
    /// Use for:
    /// - API requests/responses
    /// - Network errors
    /// - TTS provider calls
    /// - Cloud transcription
    static let network = Logger(subsystem: subsystem, category: "Network")
    
    /// Logger for storage operations
    ///
    /// Use for:
    /// - SwiftData operations
    /// - File I/O
    /// - Keychain access
    /// - UserDefaults
    static let storage = Logger(subsystem: subsystem, category: "Storage")
    
    /// Logger for general application lifecycle
    ///
    /// Use for:
    /// - App launch/termination
    /// - Initialization
    /// - Configuration
    /// - Critical errors
    static let app = Logger(subsystem: subsystem, category: "App")
    
    /// Logger for MetricKit performance metrics
    ///
    /// Use for:
    /// - CPU/memory usage reports
    /// - Launch time measurements
    /// - Hang diagnostics
    /// - Disk I/O metrics
    static let metrics = Logger(subsystem: subsystem, category: "Metrics")
    
    // MARK: - Convenience Methods
    
    /// Log a transcription event
    static func logTranscription(_ message: String, level: OSLogType = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, logger: transcription, level: level, file: file, function: function, line: line)
    }
    
    /// Log an audio event
    static func logAudio(_ message: String, level: OSLogType = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, logger: audio, level: level, file: file, function: function, line: line)
    }
    
    /// Log a Power Mode event
    static func logPowerMode(_ message: String, level: OSLogType = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, logger: powerMode, level: level, file: file, function: function, line: line)
    }
    
    /// Log an AI enhancement event
    static func logAI(_ message: String, level: OSLogType = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, logger: ai, level: level, file: file, function: function, line: line)
    }
    
    /// Log a metrics event
    static func logMetrics(_ message: String, level: OSLogType = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, logger: metrics, level: level, file: file, function: function, line: line)
    }
    
    // MARK: - Private Helpers
    
    private static func log(_ message: String, logger: Logger, level: OSLogType, file: String, function: String, line: Int) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let context = "[\(fileName):\(line) \(function)]"
        
        switch level {
        case .debug:
            logger.debug("\(context) \(message)")
        case .info:
            logger.info("\(context) \(message)")
        case .error:
            logger.error("\(context) \(message)")
        case .fault:
            logger.fault("\(context) \(message)")
        default:
            logger.log("\(context) \(message)")
        }
    }
}

// MARK: - OSLogType Extension

extension OSLogType {
    /// Human-readable description of log level
    var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        default: return "LOG"
        }
    }
}

// MARK: - Migration Helpers

#if DEBUG
/// Helper to identify print statements that should be migrated to AppLogger
///
/// Usage in development:
/// ```swift
/// // Instead of:
/// print("🎙️ Recording started")
///
/// // Use:
/// AppLogger.audio.info("Recording started")
/// ```
@available(*, deprecated, message: "Use AppLogger instead")
func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    Swift.print("⚠️ [DEPRECATED] Use AppLogger:", items, separator: separator, terminator: terminator)
}
#endif
