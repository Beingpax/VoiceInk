import Foundation
import AVFoundation
import os

#if canImport(Speech)
import Speech
#endif

/// Transcription service that leverages the new SpeechAnalyzer / SpeechTranscriber API available on macOS 26 (Tahoe).
/// Falls back with an unsupported-provider error on earlier OS versions so the application can gracefully degrade.
class NativeAppleTranscriptionService: TranscriptionService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "NativeAppleTranscriptionService")

    enum ServiceError: Error, LocalizedError {
        case unsupportedOS
        case transcriptionFailed
        case localeNotSupported
        case invalidModel
        case assetDownloadRequired(String)
        case assetReservationFailed(String)
        case resultStreamTimedOut
        
        var errorDescription: String? {
            switch self {
            case .unsupportedOS:
                return "SpeechAnalyzer requires macOS 26 or later."
            case .transcriptionFailed:
                return "Transcription failed using SpeechAnalyzer."
            case .localeNotSupported:
                return "The selected language is not supported by SpeechAnalyzer."
            case .invalidModel:
                return "Invalid model type provided for Native Apple transcription."
            case .assetDownloadRequired(let displayName):
                return "Download required for \(displayName)."
            case .assetReservationFailed(let displayName):
                return "Apple Speech could not reserve language assets for \(displayName). Manage reserved Apple Speech languages in settings."
            case .resultStreamTimedOut:
                return "Apple Speech did not finish returning transcription results."
            }
        }

        var shouldShowNotification: Bool {
            switch self {
            case .assetDownloadRequired, .assetReservationFailed:
                return true
            default:
                return false
            }
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws -> String {
        guard model is NativeAppleModel else {
            throw ServiceError.invalidModel
        }
        
        guard #available(macOS 26, *) else {
            logger.error("SpeechAnalyzer is not available on this macOS version")
            throw ServiceError.unsupportedOS
        }
        
        // Feature gated: SpeechAnalyzer/SpeechTranscriber are future APIs.
        // Enable by defining ENABLE_NATIVE_SPEECH_ANALYZER in build settings once building against macOS 26+ SDKs.
        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        let audioFile = try AVAudioFile(forReading: audioURL)
        let audioDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        
        // Apple Speech stores and consumes actual BCP-47 locale identifiers directly.
        let selectedLanguage = context.language ?? "en-US"
        guard let assetContext = await NativeAppleSpeechAssetManager.assetContext(for: selectedLanguage) else {
            let requestedIdentifier = Locale(identifier: selectedLanguage).identifier(.bcp47)
            logger.error("Transcription failed: Locale '\(requestedIdentifier, privacy: .public)' is not supported by SpeechTranscriber.")
            throw ServiceError.localeNotSupported
        }

        switch assetContext.status {
        case .installed:
            break
        case .supported, .downloading:
            logger.error("Transcription failed: Assets for '\(assetContext.localeIdentifier, privacy: .public)' are not ready. Status: \(String(describing: assetContext.status), privacy: .public).")
            throw ServiceError.assetDownloadRequired(assetContext.displayName)
        case .unsupported:
            logger.error("Transcription failed: Locale '\(assetContext.localeIdentifier, privacy: .public)' is not supported by SpeechTranscriber.")
            throw ServiceError.localeNotSupported
        @unknown default:
            logger.error("Transcription failed: Unknown Apple Speech asset status for '\(assetContext.localeIdentifier, privacy: .public)': \(String(describing: assetContext.status), privacy: .public).")
            throw ServiceError.assetDownloadRequired(assetContext.displayName)
        }
        
        guard await NativeAppleSpeechAssetManager.reserveLocaleIfNeeded(for: assetContext) else {
            throw ServiceError.assetReservationFailed(assetContext.displayName)
        }
        
        let modules: [any SpeechModule] = [assetContext.transcriber]
        let analyzer = SpeechAnalyzer(modules: modules)
        let resultTask = Task<String, Error> {
            var transcript = ""
            for try await result in assetContext.transcriber.results {
                transcript += String(result.text.characters)
            }
            return transcript
        }

        do {
            let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile)

            if let lastSampleTime {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                resultTask.cancel()
                await analyzer.cancelAndFinishNow()
                logger.error("Transcription failed: Apple Speech received no audio samples for '\(assetContext.localeIdentifier, privacy: .public)'.")
                throw ServiceError.transcriptionFailed
            }
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
        
        let resultTimeout = max(20.0, audioDuration * 4.0 + 10.0)
        let finalTranscription: String
        do {
            finalTranscription = try await waitForResultStream(
                resultTask,
                timeout: resultTimeout
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }

        return finalTranscription
        #else
        throw ServiceError.unsupportedOS
        #endif
    }

    private func waitForResultStream(
        _ resultTask: Task<String, Error>,
        timeout: TimeInterval
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await resultTask.value
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ServiceError.resultStreamTimedOut
            }

            do {
                guard let result = try await group.next() else {
                    throw ServiceError.transcriptionFailed
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                logger.error("Apple Speech result wait failed: \(error.localizedDescription, privacy: .public).")
                throw error
            }
        }
    }
} 
