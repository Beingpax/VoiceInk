import Foundation
import OSLog

enum AutoLearnLocalReviewPolicy {
    static let maximumWords = 3

    static func accepts(source: String?, destination: String) -> Bool {
        guard fitsLimits(source: source, destination: destination) else { return false }
        let target = words(destination)
        guard !target.allSatisfy({ functionWords.contains($0) }) else { return false }
        guard let source else { return true }
        let original = words(source)
        guard original.count == target.count, original != target else { return true }
        return !zip(original, target).allSatisfy { $0 == $1 || isInflection($0, $1) }
    }

    static func fitsLimits(source: String?, destination: String) -> Bool {
        let target = normalized(destination)
        let original = source.map(normalized)
        let terms = [original, target].compactMap { $0 }
        return terms.allSatisfy { term in
            !term.isEmpty && term.count <= AutoLearnLimits.maximumCandidateCharacters
                && term.split(whereSeparator: \.isWhitespace).count <= maximumWords
                && term.contains(where: \.isLetter)
                && !term.unicodeScalars.contains {
                    CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
                }
        } && original?.contains(",") != true && original != target
    }

    private static let functionWords = Set("""
        a an the is was were am are be been being do does did have has had can could shall should will
        would may might must and or but if of to in on at for from with by as it its this that these
        those i me my we us our you your he him his she her they them their not no yes which who where
        when why how there here because although unless since until while whether i'm i've i'll i'd
        you're you've you'll you'd he's he'll he'd she's she'll she'd it's it'll it'd we're we've we'll
        we'd they're they've they'll they'd isn't aren't wasn't weren't hasn't haven't hadn't doesn't
        don't didn't can't couldn't shouldn't wouldn't won't mustn't shan't there's that's who's what's
        let's
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    private static let irregularForms: [Set<String>] = [
        ["child", "children"], ["person", "people"], ["man", "men"], ["woman", "women"],
        ["mouse", "mice"], ["goose", "geese"], ["tooth", "teeth"], ["foot", "feet"],
        ["criterion", "criteria"], ["analysis", "analyses"], ["leaf", "leaves"], ["life", "lives"],
        ["go", "goes", "went", "gone"], ["run", "runs", "ran"], ["write", "writes", "wrote", "written"],
        ["see", "sees", "saw", "seen"], ["take", "takes", "took", "taken"],
        ["buy", "buys", "bought"], ["teach", "teaches", "taught"], ["think", "thinks", "thought"],
        ["feel", "feels", "felt"], ["do", "does", "did", "done"], ["have", "has", "had"],
        ["be", "am", "is", "are", "was", "were", "been"], ["come", "comes", "came"],
        ["eat", "eats", "ate", "eaten"], ["drink", "drinks", "drank", "drunk"],
        ["speak", "speaks", "spoke", "spoken"], ["good", "better", "best"], ["bad", "worse", "worst"],
    ]

    private static let irregularFormsByWord: [String: Set<String>] = {
        var index: [String: Set<String>] = [:]
        for family in irregularForms {
            for word in family { index[word, default: []].formUnion(family) }
        }
        return index
    }()
    private static let baseSuffixes = ["'s", "'", "s", "es", "ed", "ing", "er", "est", "ies", "ied", "ier", "iest"]
    private static let ySuffixes: Set<String> = ["ies", "ied", "ier", "iest"]
    private static let pluralEsSuffixes = ["s", "x", "z", "ch", "sh", "o"]
    private static let vowels = Set("aeiou")
    private static let nonDoublingConsonants = Set("wxy")

    private static func isInflection(_ first: String, _ second: String) -> Bool {
        guard first.contains(where: \.isLetter), second.contains(where: \.isLetter) else { return false }
        // A shared base must generate both complete forms.
        let candidates = possibleBases(first).union(possibleBases(second))
        return candidates.contains { base in
            var forms = regularForms(base)
            forms.insert(base)
            forms.formUnion(irregularFormsByWord[base] ?? [])
            return forms.contains(first) && forms.contains(second)
        }
    }

    private static func possibleBases(_ word: String) -> Set<String> {
        var candidates: Set<String> = [word]
        candidates.formUnion(irregularFormsByWord[word] ?? [])
        for suffix in baseSuffixes where word.hasSuffix(suffix) {
            let root = String(word.dropLast(suffix.count))
            var roots: Set<String> = [root, root + "e"]
            if ySuffixes.contains(suffix) { roots.insert(root + "y") }
            let letters = Array(root)
            if letters.count >= 2, letters.last == letters[letters.count - 2] {
                roots.insert(String(root.dropLast()))
            }
            for base in roots where base.count >= 3 || irregularFormsByWord[base] != nil {
                candidates.insert(base)
            }
        }
        return candidates
    }

    private static func regularForms(_ base: String) -> Set<String> {
        guard base.count >= 2, base.allSatisfy(\.isLetter) else { return [] }
        var forms: Set<String> = [base + "s", base + "'s", base + "ed", base + "ing",
            base + "er", base + "est"]
        if base.hasSuffix("s") { forms.insert(base + "'") }
        if pluralEsSuffixes.contains(where: { base.hasSuffix($0) }) {
            forms.insert(base + "es")
        }
        let letters = Array(base)
        if base.hasSuffix("y"), !vowels.contains(letters[letters.count - 2]) {
            let root = String(base.dropLast())
            forms.formUnion([root + "ies", root + "ied", root + "ier", root + "iest"])
        }
        if base.hasSuffix("e") {
            forms.formUnion([base + "d", base + "r", base + "st"])
            if !base.hasSuffix("ee") { forms.insert(String(base.dropLast()) + "ing") }
        }
        if letters.count >= 3, let last = letters.last,
            !vowels.contains(last), !nonDoublingConsonants.contains(last),
            vowels.contains(letters[letters.count - 2]), !vowels.contains(letters[letters.count - 3]) {
            let doubled = base + String(last)
            forms.formUnion([doubled + "ed", doubled + "ing", doubled + "er", doubled + "est"])
        }
        return forms
    }

    private static func words(_ text: String) -> [String] {
        normalized(text).lowercased().replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }
}

struct AutoLearnLocalReviewer: Sendable {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AutoLearnLocalReview")

    func review(_ candidates: [AutoLearnReviewCandidate],
        reviewID: UUID = UUID()) async throws -> [AutoLearnReviewDecision] {
        var decisions: [AutoLearnReviewDecision] = []
        for candidate in candidates {
            await Task.yield()
            try Task.checkCancellation()
            let original = candidate.originalText.precomposedStringWithCanonicalMapping
            let corrected = candidate.correctedText.precomposedStringWithCanonicalMapping
            guard original.count <= 1_024, corrected.count <= 1_024,
                let pair = CorrectionDiffEngine.replacementPair(from: .init(original: original, corrected: corrected)),
                AutoLearnLocalReviewPolicy.accepts(source: pair.source, destination: pair.destination) else {
                logger.notice("Auto Learn candidate skipped reviewID=\(reviewID.uuidString, privacy: .public) candidateID=\(candidate.candidateID.uuidString, privacy: .public) reason=localFilterRejected")
                continue
            }
            decisions.append(.init(candidateID: candidate.candidateID, learningAction: .addReplacementOnly,
                incorrectTextToReplace: pair.source, correctedVocabularyTerm: pair.destination))
        }
        return AutoLearnSuggestionLimiter.limit(decisions, candidates: candidates)
    }
}
