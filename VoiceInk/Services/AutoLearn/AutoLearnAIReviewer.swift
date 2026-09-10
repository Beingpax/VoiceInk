import Foundation
import OSLog

@MainActor
final class AutoLearnAIReviewer: @unchecked Sendable {
    private struct ReviewRequest: Encodable {
        let candidates: [AutoLearnReviewCandidate]
    }

    private struct ReviewResponse: Decodable {
        let decisions: [AutoLearnReviewDecision]
    }

    private enum ReviewError: LocalizedError {
        case unavailable
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "The configured AI enhancement provider cannot review Auto Learn candidates."
            case .invalidResponse:
                return "The AI returned an invalid Auto Learn review response."
            }
        }
    }

    private let enhancementService: AIEnhancementService
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "AutoLearnAIResponse"
    )

    init(enhancementService: AIEnhancementService) {
        self.enhancementService = enhancementService
    }

    func review(_ candidates: [AutoLearnReviewCandidate]) async throws -> [AutoLearnReviewDecision] {
        guard !candidates.isEmpty else { return [] }
        guard let aiService = enhancementService.getAIService() else {
            throw ReviewError.unavailable
        }

        let connectedProviders = aiService.connectedProviders
        guard let provider = AutoLearnSettings.selectedProvider ?? connectedProviders.first,
            connectedProviders.contains(provider)
        else {
            throw ReviewError.unavailable
        }
        let modelName: String?
        switch provider {
        case .localCLI:
            modelName = nil
        case .voiceInkRefine:
            modelName = provider.defaultModel
        default:
            modelName = AutoLearnSettings.selectedModel ?? aiService.selectedModel(for: provider)
        }

        let prompt = CustomPrompt(
            title: "Auto Learn Review",
            promptText: Self.reviewPrompt,
            useSystemInstructions: false
        )
        let configuration = EnhancementRuntimeConfiguration(
            mode: nil,
            isEnabled: true,
            prompt: prompt,
            provider: provider,
            modelName: modelName,
            useClipboardContext: false,
            useSelectedTextContext: false,
            useScreenCaptureContext: false
        )
        guard enhancementService.isConfigured(for: configuration) else {
            throw ReviewError.unavailable
        }

        let requestData = try JSONEncoder().encode(ReviewRequest(candidates: candidates))
        guard let requestText = String(data: requestData, encoding: .utf8) else {
            throw ReviewError.invalidResponse
        }

        #if DEBUG || LOCAL_BUILD
            let loggedModelName = modelName ?? "provider default"
            logger.notice(
                "Auto Learn AI request provider=\(provider.rawValue, privacy: .public) model=\(loggedModelName, privacy: .public) candidates=\(candidates.count, privacy: .public)"
            )
            logRawText(Self.reviewPrompt, label: "system prompt")
            logRawText(requestText, label: "candidate payload")
        #endif

        let responseText = try await aiService.reviewAutoLearnCandidates(
            payload: requestText,
            systemPrompt: Self.reviewPrompt,
            provider: provider,
            modelName: modelName
        )
        #if DEBUG || LOCAL_BUILD
            logRawText(responseText, label: "AI response")
        #endif
        let response = try decodeResponse(responseText)
        let expectedIDs = Set(candidates.map(\.id))
        let returnedIDs = response.decisions.map(\.id)
        guard returnedIDs.count == Set(returnedIDs).count,
            Set(returnedIDs) == expectedIDs
        else {
            throw ReviewError.invalidResponse
        }

        return response.decisions
    }

    #if DEBUG || LOCAL_BUILD
        private func logRawText(_ text: String, label: String) {
            let characters = Array(text)
            let chunkSize = 1_000
            let chunkCount = max(1, Int(ceil(Double(characters.count) / Double(chunkSize))))

            if characters.isEmpty {
                logger.notice("Auto Learn raw \(label, privacy: .public) [1/1]: <empty>")
                return
            }

            for index in 0..<chunkCount {
                let start = index * chunkSize
                let end = min(start + chunkSize, characters.count)
                let chunk = String(characters[start..<end])
                logger.notice(
                    "Auto Learn raw \(label, privacy: .public) [\(index + 1, privacy: .public)/\(chunkCount, privacy: .public)]: \(chunk, privacy: .public)"
                )
            }
        }
    #endif

    private func decodeResponse(_ text: String) throws -> ReviewResponse {
        var payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if payload.hasPrefix("```") {
            let lines = payload.split(separator: "\n", omittingEmptySubsequences: false)
            let closingFence = lines.last.map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard lines.count >= 3, closingFence == "```" else {
                throw ReviewError.invalidResponse
            }
            payload = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = payload.data(using: .utf8) else {
            throw ReviewError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(ReviewResponse.self, from: data)
        } catch {
            throw ReviewError.invalidResponse
        }
    }

    private static let reviewPrompt = """
        Review corrections the user made to speech-to-text output.

        Set accepted to true only when the destination is reusable personalized terminology: a person's name, place, company, brand, product, project, acronym, abbreviation, technical term, or other specialized vocabulary. The source must be a plausible speech-recognition, phonetic, spelling, capitalization, punctuation, or spacing error for that same intended term. The source may itself be a valid common word.

        Set accepted to false for ordinary word corrections, grammar or style edits, rewrites, meaning changes, facts, numbers, dates, unrelated substitutions between common words, and deliberate abbreviation or expansion transformations. Converting a correctly transcribed long form into its short form is an editorial change, not a speech-recognition correction.

        Examples:
        - "Nevo Karna" to "Neeve O'Connor": accepted true
        - "post gray sequel" to "PostgreSQL": accepted true
        - "k eight s" to "K8s": accepted true
        - "api" to "API": accepted true
        - "application programming interface" to "API": accepted false
        - "their" to "there": accepted false
        - "quick" to "fast": accepted false
        - "Tuesday" to "Wednesday": accepted false

        Return JSON only, with this exact shape:
        {"decisions":[{"id":"candidate UUID","accepted":true}]}

        Return every input ID exactly once. Never alter, repeat, or invent source or destination text. Do not include explanations or markdown.
        """
}
