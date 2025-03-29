import Foundation
#if canImport(whisper)
import whisper
#else
#error("Unable to import whisper module. Please check your project configuration.")
#endif
import os

enum WhisperError: Error {
    case couldNotInitializeContext
    case transcriptionFailed
    case fileNotFound
    case audioConversionFailed
}

// Meet Whisper C++ constraint: Don't access from more than one thread at a time.
actor WhisperContext: TranscriptionService {
    private var context: OpaquePointer?
    private var languageCString: [CChar]?
    private var prompt: String?
    private var promptCString: [CChar]?
    private var language: String?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperContext")

    private init() {
        // Private initializer without context
    }

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        if let context = context {
            whisper_free(context)
        }
    }
    
    /// Transcribes audio directly from a file URL
    /// - Parameter fileURL: The URL of the audio file to transcribe
    func fullTranscribeFromURL(fileURL: URL) async throws {
        guard let _ = context else {
            throw WhisperError.transcriptionFailed
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.error("❌ Audio file not found at path: \(fileURL.path)")
            throw WhisperError.fileNotFound
        }
        
        logger.notice("🔄 Starting Whisper transcription from file URL")
        
        // Read samples from audio file
        do {
            let samples = try decodeWaveFile(fileURL)
            try await fullTranscribe(samples: samples)
        } catch {
            logger.error("❌ Failed to convert audio file to samples: \(error.localizedDescription)")
            throw WhisperError.audioConversionFailed
        }
    }

    private func fullTranscribe(samples: [Float]) async throws {
        guard let context = context else {
            throw WhisperError.transcriptionFailed
        }
        
        // Leave 2 processors free (i.e. the high-efficiency cores).
        let maxThreads = max(1, min(8, cpuCount() - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        
        // Set language from stored property
        if let language = language {
            languageCString = Array(language.utf8CString)
            params.language = languageCString?.withUnsafeBufferPointer { ptr in
                ptr.baseAddress
            }
            logger.notice("🌐 Using language: \(language)")
        } else {
            languageCString = nil
            params.language = nil
            logger.notice("🌐 Using auto language detection")
        }
        
        // Use prompt for all languages
        if prompt != nil {
            promptCString = Array(prompt!.utf8CString)
            params.initial_prompt = promptCString?.withUnsafeBufferPointer { ptr in
                ptr.baseAddress
            }
            logger.notice("💬 Using prompt for transcription in language: \(self.language ?? "auto")")
        } else {
            promptCString = nil
            params.initial_prompt = nil
        }
        
        // Adapted from whisper.objc
        params.print_realtime = true
        params.print_progress = false
        params.print_timestamps = true
        params.print_special = false
        params.translate = false
        params.n_threads = Int32(maxThreads)
        params.offset_ms = 0
        params.no_context = false
        params.single_segment = false
        
        // Adjusted parameters to reduce hallucination
        params.suppress_blank = true // Keep suppressing blank outputs
        params.suppress_nst = true // Additional suppression of non-speech tokens

        whisper_reset_timings(context)
        logger.notice("⚙️ Starting whisper transcription")
        samples.withUnsafeBufferPointer { samples in
            if whisper_full(context, params, samples.baseAddress, Int32(samples.count)) != 0 {
                logger.error("❌ Failed to run whisper model")
            } else {
                // Print detected language info before timings
                let langId = whisper_full_lang_id(context)
                let detectedLang = String(cString: whisper_lang_str(langId))
                logger.notice("✅ Transcription completed - Language: \(detectedLang)")
                whisper_print_timings(context)
            }
        }
        
        languageCString = nil
        promptCString = nil
    }

    /// Decodes a wave file into an array of float samples
    private func decodeWaveFile(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        // Skip the 44-byte WAV header
        let floats = stride(from: 44, to: data.count, by: 2).map {
            data[$0..<$0 + 2].withUnsafeBytes {
                let short = Int16(littleEndian: $0.load(as: Int16.self))
                return max(-1.0, min(Float(short) / 32767.0, 1.0))
            }
        }
        return floats
    }

    func getTranscription() -> String {
        guard let context = context else { return "" }
        var transcription = ""
        for i in 0..<whisper_full_n_segments(context) {
            transcription += String(cString: whisper_full_get_segment_text(context, i))
        }
        return transcription
    }

    static func createContext(path: String) async throws -> WhisperContext {
        // Create empty context first
        let whisperContext = WhisperContext()
        
        // Initialize the context within the actor's isolated context
        try await whisperContext.initializeModel(path: path)
        
        return whisperContext
    }
    
    static func createService(configuration: [String: Any]) async throws -> WhisperContext {
        guard let modelPath = configuration["modelPath"] as? String else {
            throw WhisperError.couldNotInitializeContext
        }
        
        return try await createContext(path: modelPath)
    }
    
    private func initializeModel(path: String) throws {
        var params = whisper_context_default_params()
        #if targetEnvironment(simulator)
        params.use_gpu = false
        logger.notice("🖥️ Running on simulator, using CPU")
        #endif
        
        let context = whisper_init_from_file_with_params(path, params)
        if let context {
            self.context = context
        } else {
            logger.error("❌ Couldn't load model at \(path)")
            throw WhisperError.couldNotInitializeContext
        }
    }

    func releaseResources() {
        if let context = context {
            whisper_free(context)
            self.context = nil
        }
        languageCString = nil
    }

    func setPrompt(_ prompt: String?) {
        self.prompt = prompt
        logger.debug("💬 Prompt set: \(prompt ?? "none")")
    }
    
    func setLanguage(_ language: String?) {
        self.language = language
        logger.debug("🌐 Language set: \(language ?? "nil")")
    }
}

private func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}
