import Foundation

@MainActor
final class MeetingSummarizerRegistry {
    static let shared = MeetingSummarizerRegistry()

    // AIService is injected because it is composed (not a singleton) in VoiceInk.swift.
    // Callers must call configure(aiService:) before using currentSummarizer().
    private var aiService: AIService?
    private var _geminiSummarizer: GeminiMeetingSummarizer?

    private init() {}

    func configure(aiService: AIService) {
        self.aiService = aiService
        self._geminiSummarizer = GeminiMeetingSummarizer(aiService: aiService)
    }

    func currentSummarizer() -> any MeetingSummarizer {
        // MVP: Gemini only. Adding OpenAI/Anthropic later means a new service + a branch here.
        guard let summarizer = _geminiSummarizer else {
            // Registry was used before configure(aiService:) was called — return an unconfigured
            // instance so callers get .notConfigured rather than a crash.
            return GeminiMeetingSummarizer(aiService: AIService())
        }
        return summarizer
    }
}
