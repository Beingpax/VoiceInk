import Foundation
import SwiftData
import os

/// Handles the full post-recording pipeline:
/// transcribe → filter → format → word-replace → prompt-detect → AI enhance → start paste + dismiss → save
@MainActor
class TranscriptionPipeline {
    private let modelContext: ModelContext
    private let serviceRegistry: TranscriptionServiceRegistry
    private let enhancementService: AIEnhancementService?
    private let promptDetectionService = PromptDetectionService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionPipeline")

    var licenseViewModel: LicenseViewModel

    init(
        modelContext: ModelContext,
        serviceRegistry: TranscriptionServiceRegistry,
        enhancementService: AIEnhancementService?
    ) {
        self.modelContext = modelContext
        self.serviceRegistry = serviceRegistry
        self.enhancementService = enhancementService
        self.licenseViewModel = LicenseViewModel()
    }

    /// Run the full pipeline for a given transcription record.
    /// - Parameters:
    ///   - transcription: The pending Transcription SwiftData object to populate and save.
    ///   - audioURL: The recorded audio file.
    ///   - model: The transcription model to use.
    ///   - session: An active streaming session if one was prepared, otherwise nil.
    ///   - onStateChange: Called when the pipeline moves to a new recording state (e.g. `.enhancing`).
    ///   - shouldCancel: Returns true if the user requested cancellation.
    ///   - onCancel: Called when cancellation is detected to cancel active session state.
    ///   - onDismiss: Called as soon as paste is initiated to dismiss the recorder panel.
    func run(
        transcription: Transcription,
        audioURL: URL,
        model: any TranscriptionModel,
        session: TranscriptionSession?,
        onStateChange: @escaping (RecordingState) -> Void,
        shouldCancel: () -> Bool,
        onCancel: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void
    ) async {
        var finalPastedText: String?
        var promptDetectionResult: PromptDetectionService.PromptDetectionResult?
        var didInsertSessionMetric = false

        func restorePromptDetectionSettingsIfNeeded() async {
            if let result = promptDetectionResult,
               let enhancementService,
               result.shouldEnableAI {
                await promptDetectionService.restoreOriginalSettings(result, to: enhancementService)
            }
        }

        func restorePromptDetectionSettingsAndDismiss(afterRestore: () -> Void = {}) async {
            await restorePromptDetectionSettingsIfNeeded()
            afterRestore()
            await onDismiss()
        }

        func finishCanceledTranscription() async {
            await onCancel()
            await restorePromptDetectionSettingsIfNeeded()

            let canceledDuration: TimeInterval?
            if transcription.duration > 0 {
                canceledDuration = nil
            } else {
                let duration = await AudioFileMetadata.duration(for: audioURL)
                canceledDuration = duration > 0 ? duration : nil
            }

            transcription.markAsCanceledTranscription(
                duration: canceledDuration,
                modelName: transcription.transcriptionModelName ?? model.displayName
            )

            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save canceled transcription: \(error.localizedDescription, privacy: .public)")
            }
        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return
        }

        do {
            let transcriptionStart = Date()
            var text: String
            if let session {
                text = try await session.transcribe(audioURL: audioURL)
            } else {
                text = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
            }
            text = TranscriptionOutputFilter.filter(text)
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

            if shouldCancel() { await finishCanceledTranscription(); return }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if UserDefaults.standard.bool(forKey: "IsTextFormattingEnabled") {
                text = WhisperTextFormatter.format(text)
            }

            if UserDefaults.standard.bool(forKey: "SmartSpacingAndCapitalization") {
                text = TranscriptionPipeline.applySmartSpacingAndCapitalization(text)
            }

            text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
            let cleanedText = TranscriptionOutputFilter.applyUserCleanupPreferences(text)

            let actualDuration = await AudioFileMetadata.duration(for: audioURL)

            transcription.text = cleanedText
            transcription.duration = actualDuration
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            finalPastedText = cleanedText

            if let enhancementService, enhancementService.isConfigured {
                let detectionResult = promptDetectionService.analyzeText(text, with: enhancementService)
                promptDetectionResult = detectionResult
                await promptDetectionService.applyDetectionResult(detectionResult, to: enhancementService)
            }

            let isSkipShortEnhancementEnabled = UserDefaults.standard.bool(forKey: "SkipShortEnhancement")
            let savedThreshold = UserDefaults.standard.integer(forKey: "ShortEnhancementWordThreshold")
            let shortEnhancementWordThreshold = savedThreshold > 0 ? savedThreshold : 3
            let shouldSkipEnhancement = isSkipShortEnhancementEnabled && WordCounter.count(in: text) <= shortEnhancementWordThreshold && !(promptDetectionResult?.shouldEnableAI == true)

            if let enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured,
               !shouldSkipEnhancement {
                if shouldCancel() { await finishCanceledTranscription(); return }

                onStateChange(.enhancing)
                let textForAI = promptDetectionResult?.processedText ?? text

                do {
                    let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(textForAI)
                    transcription.enhancedText = enhancedText
                    transcription.aiEnhancementModelName = enhancementService.getAIService()?.currentModel
                    transcription.promptName = promptName
                    transcription.enhancementDuration = enhancementDuration
                    transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                    transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                    finalPastedText = enhancedText
                } catch {
                    let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    transcription.enhancedText = "Enhancement failed: \(errorDescription)"
                    let shortReason = String(errorDescription.prefix(80))
                    await MainActor.run {
                        NotificationManager.shared.showNotification(
                            title: "Enhancement failed: \(shortReason)",
                            type: .warning
                        )
                    }
                    if shouldCancel() { await finishCanceledTranscription(); return }
                }
            }

            transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue
        } catch {
            let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

            if let nativeAppleError = error as? NativeAppleTranscriptionService.ServiceError,
               case .assetDownloadRequired = nativeAppleError {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: errorDescription,
                        type: .error,
                        duration: 5.0
                    )
                }
            }

            transcription.text = "Transcription Failed: \(errorDescription)"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
        }

        func saveTranscriptionAndPostCompletion() {
            if transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
                do {
                    didInsertSessionMetric = try SessionMetricRecorder.recordRecorderSession(
                        transcription: transcription,
                        model: model,
                        in: modelContext
                    )
                } catch {
                    logger.error("Failed to record session metric: \(error.localizedDescription, privacy: .public)")
                }
            }

            do {
                try modelContext.save()
                if didInsertSessionMetric {
                    NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
                }
                NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)

                // Sync the completed transcription to local Nerv Cockpit memory or execute voice commands
                if transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
                    let textToSync = (transcription.enhancedText != nil && !transcription.enhancedText!.isEmpty && !transcription.enhancedText!.hasPrefix("Enhancement failed:")) ? transcription.enhancedText! : transcription.text
                    NervSyncService.shared.processTranscription(textToSync)
                }
            } catch {
                logger.error("Failed to save transcription: \(error.localizedDescription, privacy: .public)")
            }
        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return
        }

        var shouldPaste = true
        var textToPaste = finalPastedText ?? ""
        let activeConfig = PowerModeManager.shared.currentActiveConfiguration

        if transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
            let actionResult = AutomationActionService.shared.processActions(in: textToPaste)
            shouldPaste = actionResult.shouldPaste
            textToPaste = actionResult.cleanedText

            // Run post-recording script hook if available
            if let activeConfig,
               let postRecordScript = activeConfig.postRecordScript,
               !postRecordScript.isEmpty {
                let rawTranscript = transcription.text
                let pmName = activeConfig.name
                Task {
                    await ShellScriptService.shared.runScript(
                        postRecordScript,
                        transcript: textToPaste,
                        rawTranscript: rawTranscript,
                        powerModeName: pmName
                    )
                }
            }
        }

        if shouldPaste && !textToPaste.isEmpty,
           transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
            if case .trialExpired = licenseViewModel.licenseState {
                textToPaste = """
                    Your trial has expired. Upgrade to VoiceInk Pro at tryvoiceink.com/buy
                    \n\(textToPaste)
                    """
            }

            let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
            let pastedText = textToPaste + (appendSpace ? " " : "")
            _ = await CursorPaster.startPasteAtCursor(pastedText).value
            let autoSendKey = activeConfig?.autoSendKey
            SoundManager.shared.playStopSound()
            await restorePromptDetectionSettingsAndDismiss {
                if let autoSendKey, autoSendKey.isEnabled {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        CursorPaster.performAutoSend(autoSendKey)
                    }
                }
            }
        } else {
            SoundManager.shared.playStopSound()
            await restorePromptDetectionSettingsAndDismiss()
        }

        saveTranscriptionAndPostCompletion()
    }

    static func applySmartSpacingAndCapitalization(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove spaces before punctuation: . , ? ! : ;
        let punctuations = [".", ",", "?", "!", ":", ";"]
        for p in punctuations {
            let escapedP = NSRegularExpression.escapedPattern(for: p)
            let regex = try? NSRegularExpression(pattern: "\\s+\(escapedP)", options: [])
            text = regex?.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: p) ?? text
        }
        
        // Ensure a single space after punctuation if followed by any character that is not a whitespace
        for p in punctuations {
            let escapedP = NSRegularExpression.escapedPattern(for: p)
            let regex = try? NSRegularExpression(pattern: "\(escapedP)(?=[^\\s])", options: [])
            text = regex?.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "\(p) ") ?? text
        }
        
        // Replace multiple consecutive spaces with a single space
        let multiSpaceRegex = try? NSRegularExpression(pattern: "\\s+", options: [])
        text = multiSpaceRegex?.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: " ") ?? text
        
        // Capitalize the first letter of each sentence
        var chars = Array(text)
        var capitalizeNext = true
        for i in 0..<chars.count {
            let c = chars[i]
            if capitalizeNext {
                if c.isWhitespace {
                    continue
                } else if c.isLetter {
                    chars[i] = Character(c.uppercased())
                    capitalizeNext = false
                } else {
                    capitalizeNext = false
                }
            }
            if c == "." || c == "?" || c == "!" {
                capitalizeNext = true
            }
        }
        text = String(chars)
        
        return text
    }
}
