import Foundation
import OSLog

@MainActor
final class AutoLearnAIReviewer: @unchecked Sendable {
    private struct AutoLearnReviewRequest: Encodable {
        struct CandidateForReview: Encodable {
            let candidateID: Int
            let originalText: String
            let correctedText: String
        }

        let candidatesForReview: [CandidateForReview]
    }

    private struct AutoLearnReviewResponse: Decodable {
        let reviewDecisions: [CandidateReviewDecision]
    }

    private struct CandidateReviewDecision: Decodable {
        let candidateID: Int
        let learningAction: AutoLearnReviewAction
        let incorrectTextToReplace: String?
        let correctedVocabularyTerm: String?
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
        category: "AutoLearnAIReview"
    )

    init(enhancementService: AIEnhancementService) {
        self.enhancementService = enhancementService
    }

    /// True when a review could run right now. Used to defer queued reviews
    /// while providers are still starting up instead of recording a failure.
    var hasAvailableProvider: Bool {
        guard let aiService = enhancementService.getAIService() else { return false }
        let connectedProviders = aiService.connectedProviders.filter {
            AutoLearnProviderPolicy.isSupported($0)
                && ($0 != .ollama || !aiService.availableModels(for: $0).isEmpty)
        }
        if let selected = AutoLearnSettings.selectedProvider {
            return connectedProviders.contains(selected)
        }
        return !connectedProviders.isEmpty
    }

    func review(_ candidates: [AutoLearnReviewCandidate]) async throws -> AutoLearnReviewResult {
        guard !candidates.isEmpty else {
            return AutoLearnReviewResult(reviewDecisions: [], unresolvedReviews: [])
        }
        guard let aiService = enhancementService.getAIService() else {
            throw ReviewError.unavailable
        }

        let connectedProviders = aiService.connectedProviders.filter {
            AutoLearnProviderPolicy.isSupported($0)
                && ($0 != .ollama || !aiService.availableModels(for: $0).isEmpty)
        }
        // Respect the user's provider choice. Ollama keeps correction review on-device.
        guard let provider = AutoLearnSettings.selectedProvider ?? connectedProviders.first,
            connectedProviders.contains(provider)
        else {
            throw ReviewError.unavailable
        }
        let modelName = AutoLearnSettings.selectedModel ?? aiService.selectedModel(for: provider)

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

        let candidatesForReview = candidates.enumerated().map { index, candidate in
            AutoLearnReviewRequest.CandidateForReview(
                candidateID: index,
                originalText: candidate.originalText,
                correctedText: candidate.correctedText
            )
        }
        let requestData = try JSONEncoder().encode(
            AutoLearnReviewRequest(candidatesForReview: candidatesForReview)
        )
        guard let requestText = String(data: requestData, encoding: .utf8) else {
            throw ReviewError.invalidResponse
        }

        let loggedModelName = modelName ?? "provider-default"
        logger.notice(
            "Auto Learn review started provider=\(provider.rawValue, privacy: .public) model=\(loggedModelName, privacy: .public) candidates=\(candidates.count, privacy: .public)"
        )
        let responseText = try await aiService.reviewAutoLearnCandidates(
            payload: requestText,
            systemPrompt: Self.reviewPrompt,
            provider: provider,
            modelName: modelName
        )
        let candidateReviewDecisions = try decodeResponse(responseText)
        let expectedCandidateIDs = Set(candidates.indices)
        let decisionsByCandidateID = Dictionary(grouping: candidateReviewDecisions) {
            $0.candidateID
        }
        for unknownCandidateID in decisionsByCandidateID.keys
        where !expectedCandidateIDs.contains(unknownCandidateID) {
            logger.warning(
                "Ignoring Auto Learn decision with unknown candidate ID=\(unknownCandidateID, privacy: .public)"
            )
        }

        var reviewDecisions: [AutoLearnReviewDecision] = []
        var unresolvedReviews: [AutoLearnUnresolvedReview] = []

        let correctedTextUniverse = candidates.map(\.correctedText)

        for (index, candidate) in candidates.enumerated() {
            guard let matchingDecisions = decisionsByCandidateID[index] else {
                unresolvedReviews.append(
                    unresolvedReview(for: candidate, reason: .missingDecision)
                )
                continue
            }

            // One diff candidate can contain adjacent corrections with no
            // unchanged token between them. Let the reviewer separate those
            // terms, but never mix an accepted correction with a rejection.
            if matchingDecisions.count > 1,
                matchingDecisions.contains(where: { $0.learningAction == .rejectCorrection })
            {
                unresolvedReviews.append(
                    unresolvedReview(
                        for: candidate,
                        reason: .conflictingDecisions,
                        decision: matchingDecisions.first
                    )
                )
                continue
            }

            var validatedDecisions: [AutoLearnReviewDecision] = []
            var unresolvedDecision: AutoLearnUnresolvedReview?
            for decision in matchingDecisions {
                let validation = validate(
                    decision,
                    for: candidate,
                    correctedTextUniverse: correctedTextUniverse
                )
                guard let validatedDecision = validation.decision else {
                    unresolvedDecision = unresolvedReview(
                        for: candidate,
                        reason: validation.failure ?? .invalidRequiredActionValues,
                        decision: decision
                    )
                    break
                }
                validatedDecisions.append(validatedDecision)
            }

            if let unresolvedDecision {
                unresolvedReviews.append(unresolvedDecision)
            } else if !decisionsAreIndependent(validatedDecisions, for: candidate) {
                unresolvedReviews.append(
                    unresolvedReview(
                        for: candidate,
                        reason: .conflictingDecisions,
                        decision: matchingDecisions.first
                    )
                )
            } else {
                reviewDecisions.append(contentsOf: validatedDecisions)
            }
        }

        return AutoLearnReviewResult(
            reviewDecisions: reviewDecisions,
            unresolvedReviews: unresolvedReviews
        )
    }

    private func unresolvedReview(
        for candidate: AutoLearnReviewCandidate,
        reason: AutoLearnUnresolvedReason,
        decision: CandidateReviewDecision? = nil
    ) -> AutoLearnUnresolvedReview {
        AutoLearnUnresolvedReview(
            candidateID: candidate.candidateID,
            reason: reason,
            learningAction: decision?.learningAction,
            incorrectTextToReplace: decision?.incorrectTextToReplace,
            correctedVocabularyTerm: decision?.correctedVocabularyTerm
        )
    }

    private func validate(
        _ decision: CandidateReviewDecision,
        for candidate: AutoLearnReviewCandidate,
        correctedTextUniverse: [String]
    ) -> (decision: AutoLearnReviewDecision?, failure: AutoLearnUnresolvedReason?) {
        if decision.learningAction == .rejectCorrection {
            return (
                AutoLearnReviewDecision(
                    candidateID: candidate.candidateID,
                    learningAction: .rejectCorrection,
                    incorrectTextToReplace: nil,
                    correctedVocabularyTerm: nil
                ),
                nil
            )
        }

        guard let correctedVocabularyTerm = decision.correctedVocabularyTerm?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return (nil, .missingRequiredActionValues)
        }
        guard !correctedVocabularyTerm.isEmpty,
            correctedVocabularyTerm.count <= AutoLearnLimits.maximumCandidateCharacters,
            isGrounded(correctedVocabularyTerm, in: correctedTextUniverse)
        else {
            return (nil, .invalidRequiredActionValues)
        }

        if decision.learningAction == .addVocabularyOnly {
            return (
                AutoLearnReviewDecision(
                    candidateID: candidate.candidateID,
                    learningAction: .addVocabularyOnly,
                    incorrectTextToReplace: nil,
                    correctedVocabularyTerm: correctedVocabularyTerm
                ),
                nil
            )
        }

        guard let incorrectTextToReplace = decision.incorrectTextToReplace?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return (nil, .missingRequiredActionValues)
        }
        guard !incorrectTextToReplace.isEmpty,
            incorrectTextToReplace != correctedVocabularyTerm,
            incorrectTextToReplace.count <= AutoLearnLimits.maximumCandidateCharacters,
            isExactSubstring(incorrectTextToReplace, of: candidate.originalText)
        else {
            return (nil, .invalidRequiredActionValues)
        }

        if differsOnlyByLetterCase(incorrectTextToReplace, correctedVocabularyTerm) {
            return (
                AutoLearnReviewDecision(
                    candidateID: candidate.candidateID,
                    learningAction: .rejectCorrection,
                    incorrectTextToReplace: nil,
                    correctedVocabularyTerm: nil
                ),
                nil
            )
        }

        return (
            AutoLearnReviewDecision(
                candidateID: candidate.candidateID,
                learningAction: decision.learningAction,
                incorrectTextToReplace: incorrectTextToReplace,
                correctedVocabularyTerm: correctedVocabularyTerm
            ),
            nil
        )
    }

    private func differsOnlyByLetterCase(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .caseInsensitive) == .orderedSame
    }

    private func isExactSubstring(_ term: String, of context: String) -> Bool {
        context.range(of: term, options: .literal) != nil
    }

    private func isGrounded(_ term: String, in contexts: [String]) -> Bool {
        contexts.contains { isExactSubstring(term, of: $0) }
    }

    private func decisionsAreIndependent(
        _ decisions: [AutoLearnReviewDecision],
        for candidate: AutoLearnReviewCandidate
    ) -> Bool {
        let originalTerms = decisions.compactMap(\.incorrectTextToReplace)
        guard canLocateWithoutOverlap(originalTerms, in: candidate.originalText) else {
            return false
        }

        // Batch canonicalization may intentionally return a corrected term
        // from another candidate, so only test terms present in this snippet.
        let localCorrectedTerms = decisions.compactMap(\.correctedVocabularyTerm).filter {
            isExactSubstring($0, of: candidate.correctedText)
        }
        return canLocateWithoutOverlap(localCorrectedTerms, in: candidate.correctedText)
    }

    private func canLocateWithoutOverlap(_ terms: [String], in text: String) -> Bool {
        guard terms.count > 1 else { return true }
        let text = text as NSString
        let rangesByTerm = terms.map { term -> [NSRange] in
            var matches: [NSRange] = []
            var searchRange = NSRange(location: 0, length: text.length)
            while searchRange.length > 0 {
                let match = text.range(of: term, options: .literal, range: searchRange)
                guard match.location != NSNotFound else { break }
                matches.append(match)
                let nextLocation = match.location + 1
                guard nextLocation < text.length else { break }
                searchRange = NSRange(
                    location: nextLocation,
                    length: text.length - nextLocation
                )
            }
            return matches
        }

        func assign(_ termIndex: Int, occupied: [NSRange]) -> Bool {
            guard termIndex < rangesByTerm.count else { return true }
            for range in rangesByTerm[termIndex]
            where occupied.allSatisfy({ NSIntersectionRange($0, range).length == 0 }) {
                if assign(termIndex + 1, occupied: occupied + [range]) {
                    return true
                }
            }
            return false
        }

        return assign(0, occupied: [])
    }

    private func decodeResponse(_ text: String) throws -> [CandidateReviewDecision] {
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
            return try JSONDecoder()
                .decode(AutoLearnReviewResponse.self, from: data)
                .reviewDecisions
        } catch {
            throw ReviewError.invalidResponse
        }
    }

    private static let reviewPrompt = """
        Review user corrections to speech-to-text. Each candidate contains an originalText snippet and a correctedText snippet. Each snippet includes the edited text with up to two surrounding words on each side. Compare the snippets to identify what the user changed.

        First identify every minimal, independently reusable correction in each candidate. Normally a candidate produces one review decision. If two or more separate learnable terms were corrected next to each other with no unchanged word between them, return one review decision for each term and repeat that candidateID. Never combine independent entities into one replacement merely because their edits are adjacent. A genuinely single multiword name or term remains one correction. If a candidate contains both learnable and ordinary edits, return only the learnable corrections. Return one rejectCorrection only when the candidate contains no learnable correction; never combine rejectCorrection with an accepted decision for the same candidateID.

        Adjacent independent correction example:
        Input: {"candidateID":0,"originalText":"results with voicing prakase packs","correctedText":"results with VoiceInk Prakash Joshi Pax"}
        Decisions: [{"candidateID":0,"learningAction":"addReplacementAndVocabulary","incorrectTextToReplace":"voicing","correctedVocabularyTerm":"VoiceInk"},{"candidateID":0,"learningAction":"addReplacementAndVocabulary","incorrectTextToReplace":"prakase packs","correctedVocabularyTerm":"Prakash Joshi Pax"}]

        By contrast, "with Prakash Jossipax yesterday" to "with Prakash Joshi Pax yesterday" is one correction because both phrases refer to the same complete person name.

        Classify every identified correction with one learningAction:

        Vocabulary gate: Vocabulary is reserved for uncommon, user-specific, domain-specific, or specialized terms whose spelling would materially help future speech recognition. Do not add ordinary words, common personal names, broadly recognized organizations, mainstream products, major platforms, standard technologies, or other already well-known terms to Vocabulary merely because they are proper nouns or appeared in a correction. This gate overrides every other Vocabulary rule below. If such a term has a safe reusable mis-transcription mapping, use addReplacementOnly. If it has no safe replacement mapping, reject it rather than adding it to Vocabulary.

        1. addReplacementAndVocabulary
        Use when the corrected term passes the Vocabulary gate and the original text is a plausible transcription of the same spoken term. Phonetic similarity, not merely related meaning, is what makes a replacement safe. Judge pronunciation as well as spelling. Allow capitalization, punctuation, joined or split words, and substantial spelling differences when the phrases still sound alike.

        2. addReplacementOnly
        Use when the original and corrected terms satisfy the same strict replacement gate, but the corrected term fails the Vocabulary gate because it is generic, common, or already broadly recognized. Create the useful replacement without inserting the corrected term into Vocabulary.

        A spelling correction inside a person's name uses one of the two replacement actions when it passes the replacement gate. Include the complete name from both snippets: "Maya Jonson" to "Maya Johnson", and "Prakash Jossipax" to "Prakash Joshi Pax". Choose whether to include Vocabulary by applying the Vocabulary gate; do not add a name merely because it is a name. Simple or common personal names never qualify for Vocabulary. They may use addReplacementOnly only for a genuine reusable spelling or transcription correction that changes more than letter case.

        3. addVocabularyOnly
        Use only when the corrected term passes the Vocabulary gate but the original text is too phonetically and orthographically different to be a safe global replacement. Semantic relatedness alone is insufficient for a replacement. Return the complete corrected entity from correctedText. Uncertainty about whether two phrases sound like the same spoken term should prefer addVocabularyOnly only when the corrected term passes the Vocabulary gate.

        4. rejectCorrection
        Use when the corrected text is not reusable terminology, or the edit is ordinary wording, grammar, style, meaning, facts, numbers, dates, an unrelated rewrite, or a deliberate abbreviation or expansion. Deliberate semantic shortening is not a transcription correction: reject "application programming interface" to "API", "central processing unit" to "CPU", and "pull request" to "PR". If the original text already correctly names a term, reject additions or removals of qualifiers, editions, or generic type words, such as "PostgreSQL" to "PostgreSQL database", "Claude" to "Claude AI", "GitHub" to "GitHub Enterprise", and "Visual Studio" to "Visual Studio Code". Do not add ordinary nouns merely because they are nouns.

        A common original word may still use a replacement action when it plausibly sounds like the corrected term. Do not use addVocabularyOnly merely because the original text is an ordinary word.

        Hard replacement gate: addReplacementAndVocabulary and addReplacementOnly are allowed only when the complete original and corrected terms have recognizably similar pronunciation or differ by spelling, punctuation, or word boundaries. A case-only change never qualifies. A synonym, description, role, or semantic reference is never enough. Phrases such as "database company" and "Supabase", "our designer" and "Sofia Hernández", "cloud vendor" and "Cloudflare", or "new framework" and "SvelteKit" do not sound alike and may use addVocabularyOnly only if the corrected term passes the Vocabulary gate. Never create a global replacement for descriptive sources.

        Any correction consisting only of uppercase or lowercase letter changes is rejectCorrection. Do not create either a replacement or a Vocabulary entry for it, even when the text is a personal name, proper noun, brand, product, or specialized term. For example, a lowercase personal name changed only to title case must be rejected.

        Before classifying individual candidates, compare corrected entity terms within this request. When two or more corrected terms are clearly near-duplicate spellings or pronunciations of the same named entity, choose one canonical term from the corrected terms present in this request and use it as correctedVocabularyTerm for every related accepted candidate. Prefer the form repeated most often. If frequency is tied, prefer the clearly more complete and linguistically plausible form. Never invent a canonical spelling that is absent from all correctedText values. Never merge terms based only on related meaning, and keep the terms separate when identity is uncertain.

        Canonicalization changes only correctedVocabularyTerm. Decide learningAction independently for every candidate by comparing that candidate's original text with the selected canonical term. Never reject or downgrade one candidate merely because another candidate maps to the same canonical term.

        Canonicalization example:
        Inputs: [{"candidateID":5,"originalText":"with Prakash Jossipax today","correctedText":"with Prakash Joshi Pax today"},{"candidateID":6,"originalText":"with Prakash Joseph X today","correctedText":"with Prakash Josh Pax today"}]
        Decisions: [{"candidateID":5,"learningAction":"addReplacementAndVocabulary","incorrectTextToReplace":"Prakash Jossipax","correctedVocabularyTerm":"Prakash Joshi Pax"},{"candidateID":6,"learningAction":"addReplacementAndVocabulary","incorrectTextToReplace":"Prakash Joseph X","correctedVocabularyTerm":"Prakash Joshi Pax"}]

        Be conservative. A false acceptance is more harmful than missing a useful correction. If the edit does not clearly satisfy an acceptance rule, use rejectCorrection. If you are uncertain about any classification, identity, pronunciation, term boundary, reusability, or required response value, use rejectCorrection. Use addVocabularyOnly for a phonetically distant original phrase only when the corrected term clearly passes the Vocabulary gate.

        Select complete term boundaries from the context. For every person's name, return the maximal contiguous person name visible in both contexts—not only the edited component. If a surname changes, include its unchanged given and middle names. If a given name changes, include its unchanged surname. This rule is mandatory for all accepted actions, even when the changed component alone could be reusable. Apply the same complete-boundary rule to multiword entities and specialized terms. Do not include surrounding sentence words.

        Never return only a changed surname or name fragment when an unchanged adjacent name component belongs to the same person. Follow these exact boundary examples:

        Input: {"candidateID":1,"originalText":"with Prakash Jossipax yesterday","correctedText":"with Prakash Joshi Pax yesterday"}
        Decision: {"candidateID":1,"learningAction":"addReplacementAndVocabulary","incorrectTextToReplace":"Prakash Jossipax","correctedVocabularyTerm":"Prakash Joshi Pax"}

        Input: {"candidateID":2,"originalText":"met Maya Jonson yesterday","correctedText":"met Maya Johnson yesterday"}
        Decision: {"candidateID":2,"learningAction":"addReplacementOnly","incorrectTextToReplace":"Maya Jonson","correctedVocabularyTerm":"Maya Johnson"}

        Input: {"candidateID":3,"originalText":"heard Satya Nadela speak","correctedText":"heard Satya Nadella speak"}
        Decision: {"candidateID":3,"learningAction":"addReplacementOnly","incorrectTextToReplace":"Satya Nadela","correctedVocabularyTerm":"Satya Nadella"}

        Input: {"candidateID":4,"originalText":"a film by Hiao Miyazaki","correctedText":"a film by Hayao Miyazaki"}
        Decision: {"candidateID":4,"learningAction":"addReplacementOnly","incorrectTextToReplace":"Hiao Miyazaki","correctedVocabularyTerm":"Hayao Miyazaki"}

        For addReplacementAndVocabulary, incorrectTextToReplace is the complete erroneous term and correctedVocabularyTerm is the complete corrected term to store in Vocabulary. incorrectTextToReplace must be an exact contiguous substring of that candidate's originalText. Unless batch canonicalization applies, correctedVocabularyTerm must be an exact contiguous substring of that candidate's correctedText. When canonicalization applies, correctedVocabularyTerm may instead be copied exactly from another candidate's correctedText in this request.

        For addReplacementOnly, return the same fields as addReplacementAndVocabulary. correctedVocabularyTerm is the replacement destination but must not be added to Vocabulary.

        For addVocabularyOnly, set incorrectTextToReplace to null and return the complete corrected entity as correctedVocabularyTerm. Apply the same correctedVocabularyTerm canonicalization rule described above.

        For rejectCorrection, set incorrectTextToReplace and correctedVocabularyTerm to null.

        Return JSON only in this exact shape:
        {"reviewDecisions":[{"candidateID":0,"learningAction":"addReplacementAndVocabulary","incorrectTextToReplace":"complete original term","correctedVocabularyTerm":"complete corrected term"}]}

        Allowed learningAction values are addReplacementAndVocabulary, addReplacementOnly, addVocabularyOnly, and rejectCorrection. Copy every integer candidateID exactly and return every input candidateID at least once. Repeat a candidateID only when returning separate adjacent corrections, and never return rejectCorrection together with an accepted correction for the same candidateID. Copy incorrectTextToReplace from its candidate's originalText. Copy correctedVocabularyTerm from a correctedText value in this request. Do not include explanations or markdown.
        """
}
