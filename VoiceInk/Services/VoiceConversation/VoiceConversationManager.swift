import Foundation
import AVFoundation
import SwiftData
import LLMkit
import os

enum VoiceConversationState: String {
    case idle
    case listening
    case thinking
    case speaking
}

@MainActor
class VoiceConversationManager: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VoiceConversationManager")

    @Published var state: VoiceConversationState = .idle
    @Published var currentTranscript = ""
    @Published var lastAssistantResponse = ""

    let history = ConversationHistory()
    let ttsService = TTSService()

    private let aiService: AIService
    private let transcriptionModelManager: TranscriptionModelManager
    private let serviceRegistry: TranscriptionServiceRegistry
    private let recorder = Recorder()

    var windowManager: VoiceLoopWindowManager?

    private var currentTask: Task<Void, Never>?
    private var currentRecordingURL: URL?

    var systemPrompt = """
        You are a patient, thorough teacher. The user is a developer who wants to deeply \
        understand concepts. Explain clearly, use analogies, and build understanding step by step. \
        Keep answers focused but don't oversimplify. If the user seems to understand, go deeper. \
        Respond conversationally — this will be spoken aloud.
        """

    private let recordingsDirectory: URL

    init(
        aiService: AIService,
        transcriptionModelManager: TranscriptionModelManager,
        whisperModelManager: WhisperModelManager,
        modelContext: ModelContext
    ) {
        self.aiService = aiService
        self.transcriptionModelManager = transcriptionModelManager
        self.serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: whisperModelManager,
            modelsDirectory: whisperModelManager.modelsDirectory,
            modelContext: modelContext
        )

        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("ConversationRecordings")

        // Ensure recordings directory exists
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Hotkey Handlers

    func onKeyDown() {
        windowManager?.show()

        switch state {
        case .idle:
            startListening()
        case .speaking:
            // Interrupt TTS, start listening
            ttsService.stop()
            startListening()
        case .thinking:
            // Cancel current LLM request, start listening
            currentTask?.cancel()
            currentTask = nil
            startListening()
        case .listening:
            // Already listening, ignore
            break
        }
    }

    func onKeyUp() {
        guard state == .listening, isRecorderReady else { return }
        stopListeningAndProcess()
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        ttsService.stop()
        recorder.stopRecording()
        state = .idle
        currentTranscript = ""
        lastAssistantResponse = ""
        history.clear()
        windowManager?.hide()
    }

    // MARK: - State Transitions

    private var isRecorderReady = false

    private func startListening() {
        state = .listening
        currentTranscript = ""
        isRecorderReady = false

        let url = recordingsDirectory.appendingPathComponent("conversation_\(UUID().uuidString).m4a")
        currentRecordingURL = url

        Task {
            do {
                try await recorder.startRecording(toOutputFile: url)
                isRecorderReady = true
                logger.info("Conversation recording started")
            } catch {
                logger.error("Failed to start recording: \(error.localizedDescription, privacy: .public)")
                state = .idle
            }
        }
    }

    private func stopListeningAndProcess() {
        recorder.stopRecording()
        state = .thinking

        guard let audioURL = currentRecordingURL else {
            logger.error("No recording URL available")
            state = .idle
            return
        }

        currentTask = Task {
            await runPipeline(audioURL: audioURL)
        }
    }

    // MARK: - Pipeline

    private func runPipeline(audioURL: URL) async {
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        do {
            // 1. Transcribe
            guard let model = transcriptionModelManager.currentTranscriptionModel else {
                logger.error("No transcription model selected")
                state = .idle
                return
            }

            let transcript = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)

            guard !Task.isCancelled else { return }

            let trimmed = transcript.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                logger.info("Empty transcription, returning to idle")
                state = .idle
                return
            }

            currentTranscript = trimmed
            logger.info("Transcribed: \(trimmed, privacy: .public)")

            // 2. Add to history
            history.append(role: .user, content: trimmed)

            // 3. LLM call with conversation history
            let response = try await callLLM(messages: history.asLLMMessages())

            guard !Task.isCancelled else { return }

            let trimmedResponse = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmedResponse.isEmpty else {
                logger.warning("Empty LLM response")
                state = .idle
                return
            }

            // 4. Add assistant response to history
            history.append(role: .assistant, content: trimmedResponse)
            lastAssistantResponse = trimmedResponse

            // 5. Speak the response
            state = .speaking
            await ttsService.speak(text: trimmedResponse)

            guard !Task.isCancelled else { return }

            // 6. Done speaking, return to idle (HUD stays with transcript)
            state = .idle

        } catch {
            if !Task.isCancelled {
                logger.error("Pipeline error: \(error.localizedDescription, privacy: .public)")
                state = .idle
            }
        }
    }

    // MARK: - LLM Call

    private func callLLM(messages: [ChatMessage]) async throws -> String {
        let timeout: TimeInterval = 60 // Longer timeout for conversational responses

        switch aiService.selectedProvider {
        case .anthropic:
            return try await AnthropicLLMClient.chatCompletion(
                apiKey: aiService.apiKey,
                model: aiService.currentModel,
                messages: messages,
                systemPrompt: systemPrompt,
                timeout: timeout
            )
        case .ollama:
            // Build a combined prompt for Ollama
            let combinedPrompt = messages.map { msg in
                if msg.role == "user" {
                    return "User: \(msg.content)"
                } else {
                    return "Assistant: \(msg.content)"
                }
            }.joined(separator: "\n")
            return try await aiService.enhanceWithOllama(text: combinedPrompt, systemPrompt: systemPrompt)
        default:
            guard let baseURL = URL(string: aiService.selectedProvider.baseURL) else {
                throw VoiceConversationError.invalidProviderURL
            }
            return try await OpenAILLMClient.chatCompletion(
                baseURL: baseURL,
                apiKey: aiService.apiKey,
                model: aiService.currentModel,
                messages: messages,
                systemPrompt: systemPrompt,
                temperature: 0.7,
                timeout: timeout
            )
        }
    }
}

enum VoiceConversationError: LocalizedError {
    case invalidProviderURL
    case noModel

    var errorDescription: String? {
        switch self {
        case .invalidProviderURL: return "Invalid AI provider URL"
        case .noModel: return "No transcription model selected"
        }
    }
}
