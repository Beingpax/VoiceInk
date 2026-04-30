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
            case .resultStreamTimedOut:
                return "Apple Speech did not finish returning transcription results."
            }
        }
    }

    private func languageDisplayName(for localeIdentifier: String) -> String {
        LanguageDictionary.appleNative[localeIdentifier]
            ?? Locale.current.localizedString(forIdentifier: localeIdentifier)
            ?? localeIdentifier
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
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
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en-US"
        let locale = Locale(identifier: selectedLanguage)

        let supportedLocales = await SpeechTranscriber.supportedLocales
        let installedLocales = await SpeechTranscriber.installedLocales
        let supportedIdentifiers = Set(supportedLocales.map { $0.identifier(.bcp47) })
        let installedIdentifiers = Set(installedLocales.map { $0.identifier(.bcp47) })
        let isLocaleSupported = supportedIdentifiers.contains(locale.identifier(.bcp47))
        let isLocaleInstalled = installedIdentifiers.contains(locale.identifier(.bcp47))
        
        let selectedLocaleIdentifier = locale.identifier(.bcp47)
        let displayName = languageDisplayName(for: selectedLocaleIdentifier)

        guard isLocaleSupported else {
            logger.error("Transcription failed: Locale '\(locale.identifier(.bcp47), privacy: .public)' is not supported by SpeechTranscriber.")
            throw ServiceError.localeNotSupported
        }

        guard isLocaleInstalled else {
            logger.error("Transcription failed: Assets for '\(selectedLocaleIdentifier, privacy: .public)' are not downloaded.")
            throw ServiceError.assetDownloadRequired(displayName)
        }
        
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        
        await ensureModelIsReserved(for: locale, transcriber: transcriber)
        
        let modules: [any SpeechModule] = [transcriber]
        let analyzer = SpeechAnalyzer(modules: modules)
        let resultTask = Task<String, Error> {
            var transcript = ""
            for try await result in transcriber.results {
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
                logger.error("Transcription failed: Apple Speech received no audio samples for '\(selectedLocaleIdentifier, privacy: .public)'.")
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
    
    
    
    @available(macOS 26, *)
    private func ensureModelIsReserved(for locale: Locale, transcriber: SpeechTranscriber) async {
        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        let localeIdentifier = locale.identifier(.bcp47)
        let reservedLocales = await AssetInventory.reservedLocales
        guard !reservedLocales.contains(where: { $0.identifier(.bcp47) == localeIdentifier }) else {
            return
        }

        for reservedLocale in reservedLocales {
            await AssetInventory.release(reservedLocale: reservedLocale)
        }

        do {
            let reserved = try await AssetInventory.reserve(locale: locale)

            guard reserved else {
                let finalStatus = await AssetInventory.status(forModules: [transcriber])
                logger.warning("Apple Speech asset reservation returned false for '\(localeIdentifier, privacy: .public)'. Continuing because the locale is already downloaded. Status: \(String(describing: finalStatus), privacy: .public).")
                return
            }
        } catch {
            let finalStatus = await AssetInventory.status(forModules: [transcriber])
            logger.warning("Apple Speech asset reservation failed for '\(localeIdentifier, privacy: .public)': \(error.localizedDescription, privacy: .public). Continuing because the locale is already downloaded. Status: \(String(describing: finalStatus), privacy: .public).")
        }
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
