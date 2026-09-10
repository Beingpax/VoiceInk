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
                return String(
                    localized: "The configured AI enhancement provider cannot review Auto Learn candidates."
                )
            case .invalidResponse:
                return String(localized: "The AI returned an invalid Auto Learn review response.")
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
        // Respect the user's provider choice. Ollama keeps correction review on-device.
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

        let loggedModelName = modelName ?? "provider default"
        logger.notice(
            "Auto Learn AI request provider=\(provider.rawValue, privacy: .public) model=\(loggedModelName, privacy: .public) candidates=\(candidates.count, privacy: .public)"
        )
        logRawText(Self.reviewPrompt, label: "system prompt")
        logRawText(requestText, label: "candidate payload")

        let responseText = try await aiService.reviewAutoLearnCandidates(
            payload: requestText,
            systemPrompt: Self.reviewPrompt,
            provider: provider,
            modelName: modelName
        )
        logRawText(responseText, label: "AI response")
        let response = try decodeResponse(responseText)
        let expectedIDs = Set(candidates.map(\.id))
        let returnedIDs = response.decisions.map(\.id)
        guard returnedIDs.count == Set(returnedIDs).count,
            Set(returnedIDs) == expectedIDs
        else {
            throw ReviewError.invalidResponse
        }

        let candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        return try response.decisions.map { decision in
            guard decision.accepted else {
                return AutoLearnReviewDecision(
                    id: decision.id,
                    accepted: false,
                    source: nil,
                    destination: nil
                )
            }

            guard let candidate = candidatesByID[decision.id],
                let source = decision.source?.trimmingCharacters(in: .whitespacesAndNewlines),
                let destination = decision.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
                !source.isEmpty,
                !destination.isEmpty,
                source != destination,
                source.count <= AutoLearnLimits.maximumCandidateCharacters,
                destination.count <= AutoLearnLimits.maximumCandidateCharacters,
                candidate.source.range(of: source, options: .literal) != nil,
                candidate.destination.range(of: destination, options: .literal) != nil,
                source.range(of: candidate.changedSource, options: .literal) != nil,
                destination.range(of: candidate.changedDestination, options: .literal) != nil
            else {
                throw ReviewError.invalidResponse
            }

            return AutoLearnReviewDecision(
                id: decision.id,
                accepted: true,
                source: source,
                destination: destination
            )
        }
    }

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
        Review corrections the user made to speech-to-text output. Each source and destination is a short window containing the changed text plus up to two unchanged terms on each side. changedSource and changedDestination identify the detected edit.

        Accept only reusable corrections for the same spoken term: a person's name, place, company, brand, product, project, acronym, abbreviation, technical term, specialized vocabulary, or a word whose speech-recognition output was incorrectly joined or split. The source must be a plausible phonetic, spelling, capitalization, punctuation, or spacing transcription error for that same spoken term.

        A phonetic transcription error may resemble a different ordinary word or name and may contain a different number of written words. Accept it when the complete source plausibly sounds like the complete destination and the destination is reusable terminology. For example, accept "Claudia" to "Claude AI", "get hub" to "GitHub", and "post gray sequel" to "PostgreSQL".

        Accept joining or splitting word boundaries when meaning is unchanged, such as "data base" to "database" or "web hook" to "webhook".

        Reject capitalization-only changes for ordinary words, such as "apple" to "Apple" or "sun" to "Sun". Accept capitalization or stylization when it identifies a proper name, brand, product, project, acronym, or specialized term, such as "open ai" to "OpenAI" or "get hub" to "GitHub".

        Reject genuinely added or removed meaning, qualifiers, product editions, or specificity when the source already correctly names a term. For example, reject "Claude" to "Claude AI", "GitHub" to "GitHub Enterprise", "Visual Studio" to "Visual Studio Code", and "PostgreSQL" to "PostgreSQL database". Do not apply this rejection when the whole source is instead a phonetic misrecognition of the whole destination, such as "Claudia" to "Claude AI".

        Reject ordinary wording, grammar or style edits, rewrites, meaning changes, facts, numbers, dates, unrelated substitutions, and deliberate abbreviation or expansion transformations. In particular, reject "application programming interface" to "API", "central processing unit" to "CPU", and "pull request" to "PR".

        For an accepted correction, return the exact complete term to store. Include unchanged nearby words only when they belong to the name or specialized term. The returned source must be a contiguous substring of source and contain changedSource. The returned destination must be a contiguous substring of destination and contain changedDestination. Copy text exactly; never invent or normalize it.

        Example input:
        {"id":"candidate UUID","source":"with Wojciech says me yesterday","destination":"with Wojciech Szczęsny yesterday","changedSource":"says me","changedDestination":"Szczęsny"}

        Example output:
        {"id":"candidate UUID","accepted":true,"source":"Wojciech says me","destination":"Wojciech Szczęsny"}

        Return JSON only, with this exact shape:
        {"decisions":[{"id":"candidate UUID","accepted":true,"source":"exact source term","destination":"exact destination term"}]}

        For rejected corrections, set source and destination to null. Return every input ID exactly once. Do not include explanations or markdown.
        """
}
