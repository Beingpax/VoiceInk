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
            // Hitting this means composition root forgot to call configure(aiService:) — a programmer error,
            // not a runtime failure mode. Fail loudly in debug; crash cleanly in release.
            assertionFailure("MeetingSummarizerRegistry.currentSummarizer() called before configure(aiService:)")
            fatalError("MeetingSummarizerRegistry was not configured")
        }
        return summarizer
    }
}
