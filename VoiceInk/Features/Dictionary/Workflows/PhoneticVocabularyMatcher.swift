import Foundation

/// Matches supplied vocabulary using spelling and approximate pronunciation.
/// Prepare off the main actor when vocabulary changes, then reuse for transcripts.
struct PhoneticVocabularyMatcher: Sendable {
    private enum Policy {
        case conservative, balanced

        var threshold: Double {
            switch self { case .conservative: return 0.19; case .balanced: return 0.24 }
        }
        var phoneticLimit: Double {
            switch self { case .conservative: return 0.18; case .balanced: return 0.30 }
        }
    }

    private struct Correction {
        let range: NSRange
        let replacement: String
    }

    private struct Term: Sendable {
        let text: String
        let words: [String]
        let key: String
        let phone: String
        let wordPhones: [String]
    }

    private struct Token {
        let range: NSRange
        let text: String
        let key: String
        let phone: String
        let literal: Bool
    }

    private struct Proposal {
        let end: Int
        let edit: Correction
        let gain: Double
    }

    private let terms: [Term]
    private let phoneIndex: [String: [Int]]
    private let gramIndex: [String: [Int]]
    private let exact: Set<String>
    private let maximumSpan: Int

    init(vocabulary: [String]) {
        var prepared: [Term] = []
        var phones: [String: [Int]] = [:]
        var grams: [String: [Int]] = [:]
        var known = Set<String>()
        var seen = Set<String>()
        var longest = 1
        for text in vocabulary.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).sorted() {
            let words = text.split(whereSeparator: \.isWhitespace).map { Self.normalize(String($0)) }
            guard !words.isEmpty, words.count <= 6,
                words.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (97...122).contains($0) }) })
            else { continue }
            known.insert(words.joined(separator: " "))
            let key = words.joined()
            guard key.count >= 3, key.count <= 64, seen.insert(text).inserted else { continue }
            let wordPhones = words.map(VocabularyPhonetics.key)
            let term = Term(text: text, words: words, key: key,
                phone: VocabularyPhonetics.phraseKeyFromCodes(wordPhones), wordPhones: wordPhones)
            let id = prepared.count
            prepared.append(term)
            phones[term.phone, default: []].append(id)
            for gram in Self.grams(key, includeBigrams: true) { grams[gram, default: []].append(id) }
            longest = max(longest, words.count)
        }
        terms = prepared
        phoneIndex = phones
        gramIndex = grams
        exact = known
        maximumSpan = min(8, max(4, longest + 1))
    }

    func correct(_ input: String) -> String {
        guard !terms.isEmpty else { return input }
        let tokens = Self.tokenize(input)
        guard !tokens.isEmpty else { return input }
        let source = input as NSString
        // Find supplied terms already present, including multiword names.
        var protected: [(start: Int, end: Int, words: [String])] = []
        for first in tokens.indices where !tokens[first].literal {
            var words: [String] = []
            for last in first..<min(tokens.count, first + maximumSpan) {
                guard !tokens[last].literal else { break }
                if last > first {
                    let gapRange = NSRange(location: NSMaxRange(tokens[last - 1].range),
                        length: tokens[last].range.location - NSMaxRange(tokens[last - 1].range))
                    let gap = source.substring(with: gapRange)
                    guard !gap.isEmpty, gap.allSatisfy({ $0 == " " || $0 == "\t" }) else { break }
                }
                words.append(tokens[last].key)
                if exact.contains(words.joined(separator: " ")) {
                    protected.append((first, last + 1, words))
                }
            }
        }
        var choices = [[Proposal]](repeating: [], count: tokens.count)

        for start in tokens.indices where !tokens[start].literal {
            var words: [String] = []
            var wordPhones: [String] = []
            for end in start..<min(tokens.count, start + maximumSpan) {
                let token = tokens[end]
                guard !token.literal else { break }
                if end > start {
                    let gapRange = NSRange(location: NSMaxRange(tokens[end - 1].range),
                        length: token.range.location - NSMaxRange(tokens[end - 1].range))
                    let gap = source.substring(with: gapRange)
                    guard !gap.isEmpty, gap.allSatisfy({ $0 == " " || $0 == "\t" }) else { break }
                }
                words.append(token.key)
                wordPhones.append(token.phone)
                let phrase = words.joined(separator: " ")
                guard !exact.contains(phrase) else { continue }
                if words.count == 1 && token.key.count < 4 { continue }
                if words.count > 1 && tokens[start...end].contains(where: {
                    $0.key.count == 1 && $0.text != $0.text.uppercased()
                }) { continue }
                let key = words.joined()
                guard key.count >= 4, key.count <= 64 else { continue }
                let phone = VocabularyPhonetics.phraseKeyFromCodes(wordPhones)
                let ids = candidateIDs(key: key, phone: phone)
                var matches: [(id: Int, cost: Double, policy: Policy)] = []
                for id in ids {
                    let policy = policy(for: words, wordPhones: wordPhones, term: terms[id])
                    if let cost = cost(words: words, wordPhones: wordPhones, key: key, phone: phone, term: terms[id], policy: policy) {
                        matches.append((id, cost, policy))
                    }
                }
                matches.sort { $0.cost == $1.cost ? terms[$0.id].text < terms[$1.id].text : $0.cost < $1.cost }
                guard let best = matches.first, best.cost < best.policy.threshold else { continue }
                // Reject close competitors rather than allowing vocabulary order
                // to choose a spelling. Thresholds are policies, not probabilities.
                if matches.count > 1 && matches[1].cost - best.cost < 0.04 { continue }
                let term = terms[best.id]
                // Never rewrite a fragment of an already correct term. A
                // larger correction may retain the complete term unchanged.
                if protected.contains(where: { span in
                    guard span.start < end + 1 && span.end > start else { return false }
                    guard span.start >= start, span.end <= end + 1,
                        term.words.count >= span.words.count else { return true }
                    return !(0...(term.words.count - span.words.count)).contains(where: { offset in
                        Array(term.words[offset..<(offset + span.words.count)]) == span.words
                    })
                }) { continue }
                if words.count == 1 {
                    let bestEdits = Self.editDistance(key, term.key)
                    // Do not hide a similarly spelled competitor merely because
                    // its approximate pronunciation crossed a hard filter.
                    if ids.contains(where: { id in
                        id != best.id && terms[id].words.count == 1
                            && Self.editDistance(key, terms[id].key) <= bestEdits
                            && VocabularyPhonetics.distance(phone, terms[id].phone) <= 0.5
                    }) { continue }
                }
                let range = NSRange(location: tokens[start].range.location,
                    length: NSMaxRange(token.range) - tokens[start].range.location)
                let original = source.substring(with: range)
                let replacement = original == original.uppercased() ? term.text.uppercased() : term.text
                guard original != replacement else { continue }
                choices[start].append(Proposal(end: end + 1,
                    edit: Correction(range: range, replacement: replacement),
                    gain: (1 - best.cost) * Double(term.words.count)))
            }
        }

        // Select compatible edits using supported vocabulary components and
        // similarity. Rewarding character edits instead favors a damaged suffix
        // over the exact joined spelling of a split name.
        var gains = [Double](repeating: 0, count: tokens.count + 1)
        var selected = [Proposal?](repeating: nil, count: tokens.count)
        for i in tokens.indices.reversed() {
            gains[i] = gains[i + 1]
            for proposal in choices[i].sorted(by: { $0.end < $1.end }) {
                let gain = proposal.gain + gains[proposal.end]
                if gain > gains[i] + 0.000_001 {
                    gains[i] = gain
                    selected[i] = proposal
                }
            }
        }
        var edits: [Correction] = []
        var position = 0
        while position < tokens.count {
            if let proposal = selected[position] { edits.append(proposal.edit); position = proposal.end }
            else { position += 1 }
        }
        guard !edits.isEmpty else { return input }
        let output = NSMutableString(string: input)
        for edit in edits.reversed() { output.replaceCharacters(in: edit.range, with: edit.replacement) }
        return String(output)
    }

    private func candidateIDs(key: String, phone: String) -> [Int] {
        var result = Set<Int>()
        let direct = phoneIndex[phone, default: []]
        guard direct.count <= 128 else { return [] }
        result.formUnion(direct)
        for gram in Self.grams(key) {
            let bucket = gramIndex[gram, default: []]
            // A ubiquitous gram provides little retrieval information. Avoid
            // scanning huge buckets; ambiguous oversized retrieval abstains.
            if bucket.count <= 256 { result.formUnion(bucket) }
            if result.count > 256 { return [] }
        }
        return result.sorted()
    }

    /// Exact components can anchor one weaker component. Without an exact
    /// anchor, every component must be close and the first letter must agree.
    /// Standalone words retain the conservative policy.
    private func policy(for words: [String], wordPhones: [String], term: Term) -> Policy {
        guard words.count == term.words.count, words.count >= 2, term.key.count >= 10 else {
            return .conservative
        }
        var exactMatches = 0
        var strongMatches = 0
        for (index, pair) in zip(words, term.words).enumerated() {
            let (source, target) = pair
            if source == target {
                exactMatches += 1
                strongMatches += 1
            } else {
                let spelling = Double(Self.editDistance(source, target)) / Double(max(source.count, target.count))
                let sound = VocabularyPhonetics.distance(wordPhones[index], term.wordPhones[index])
                if spelling <= 0.2 && sound <= 0.35 { strongMatches += 1 }
            }
        }
        let anchored = exactMatches > 0 && strongMatches >= words.count - 1
        let allClose = strongMatches == words.count && words.first?.first == term.words.first?.first
        return anchored || allClose ? .balanced : .conservative
    }

    private func cost(words: [String], wordPhones: [String], key: String, phone: String, term: Term, policy: Policy) -> Double? {
        // A complete, already correct term must not consume neighboring words.
        // Check full phrases as well as the standalone entries protected below.
        if term.words.count > 1 && words.count > term.words.count {
            for start in 0...(words.count - term.words.count) {
                if Array(words[start..<(start + term.words.count)]) == term.words { return nil }
            }
        }
        let length = max(key.count, term.key.count)
        guard Double(min(key.count, term.key.count)) / Double(length) >= 0.65 else { return nil }
        // A canonical word must not be fuzzily changed into another vocabulary
        // word. Larger phrase matches may preserve it at the same position.
        if words.count == 1 && exact.contains(key) { return nil }
        // A correct vocabulary term is already a complete explanation of its
        // own words. Do not absorb adjacent words into that term on another pass.
        if words.count != term.words.count && words.contains(where: exact.contains) { return nil }
        if policy == .conservative && key.first != term.key.first { return nil }
        if words.count == 1 && term.key.count <= 4 { return nil }
        let edits = Self.editDistance(key, term.key)
        let spelling = Double(edits) / Double(length)
        guard spelling <= 0.42 else { return nil }
        // Identical letters with a different word split do not need an
        // approximate encoder to agree about vowel positions at boundaries.
        var sound = key == term.key ? 0 : VocabularyPhonetics.distance(phone, term.phone)
        // Spelling evidence can explain a bounded encoder disagreement.
        if words.count == 1 && term.words.count == 1 && term.key.count >= 5
            && key.count >= 4 && ((edits == 1 && term.key.count >= 7 && key.count >= 6 && key.count != term.key.count) || Self.isAdjacentTransposition(key, term.key)) && sound <= 0.5 {
            sound = min(sound, policy.phoneticLimit)
        }
        guard sound <= policy.phoneticLimit else { return nil }

        if policy == .conservative && words.count == 1 && sound == 0 {
            if length <= 6 && edits > 1 { return nil }
            let consonants: (String) -> String = { String($0.filter { !"aeiouy".contains($0) }) }
            if consonants(key) == consonants(term.key) {
                // Consonant-only encoders erase vowels. Do not let that alone
                // justify rewriting short homophones or large vowel changes.
                if edits > 1 || (key.count == term.key.count && length <= 6) { return nil }
            }
        }

        if policy == .conservative && words.count == 1 && key.count <= 5 && sound == 0 {
            // Very short homophones provide insufficient evidence. Likewise a
            // short prefix can be an independent word, not a truncated name.
            if term.key.count <= 5 || term.key.hasPrefix(key) { return nil }
        }
        if words.count == term.words.count && words.count > 1 {
            for (index, pair) in zip(words, term.words).enumerated() where pair.0 != pair.1 {
                let (source, target) = pair
                if exact.contains(source) { return nil }
                let ratio = Double(min(source.count, target.count)) / Double(max(source.count, target.count))
                let localSound = VocabularyPhonetics.distance(wordPhones[index], term.wordPhones[index])
                if target.count <= 3 {
                    guard ratio >= 0.75, localSound == 0 else { return nil }
                } else if policy == .conservative && (ratio < 0.65 || localSound > 0.25) { return nil }
            }
        }
        let boundaryPenalty = 0.012 * Double(abs(words.count - term.words.count))
        return 0.55 * spelling + 0.45 * sound + boundaryPenalty
    }

    private static func isAdjacentTransposition(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        let changes = a.indices.filter { a[$0] != b[$0] }
        guard changes.count == 2, changes[1] == changes[0] + 1 else { return false }
        let i = changes[0], j = changes[1]
        return a[i] == b[j] && a[j] == b[i]
    }

    private static func normalize(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func grams(_ word: String, includeBigrams: Bool = false) -> Set<String> {
        let a = Array(word.utf8)
        let size = a.count <= 4 ? 2 : 3
        guard a.count >= size else { return [] }
        var result = Set((0...(a.count - size)).map { String(decoding: a[$0..<($0 + size)], as: UTF8.self) })
        if includeBigrams && a.count > 4 {
            result.formUnion((0..<(a.count - 1)).map { String(decoding: a[$0..<($0 + 2)], as: UTF8.self) })
        }
        return result
    }

    /// Restricted Damerau–Levenshtein: supports multiple insertions, deletions,
    /// substitutions, and adjacent transpositions. Strings are bounded at 64.
    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        var before = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        for i in a.indices {
            var row = [Int](repeating: 0, count: b.count + 1)
            row[0] = i + 1
            for j in b.indices {
                row[j + 1] = min(previous[j + 1] + 1, row[j] + 1, previous[j] + (a[i] == b[j] ? 0 : 1))
                if i > 0 && j > 0 && a[i] == b[j - 1] && a[i - 1] == b[j] {
                    row[j + 1] = min(row[j + 1], before[j - 1] + 1)
                }
            }
            before = previous
            previous = row
        }
        return previous[b.count]
    }

    private static let wordPattern = try! NSRegularExpression(pattern: "[\\p{L}\\p{M}\\p{N}]+(?:['’_-][\\p{L}\\p{M}\\p{N}]+)*")

    private static func tokenize(_ input: String) -> [Token] {
        let source = input as NSString
        let length = source.length
        var chunks: [(NSRange, Bool)] = []
        var location = 0
        for part in input.components(separatedBy: .whitespacesAndNewlines) {
            let size = (part as NSString).length
            if size > 0 {
                let hasDigits = part.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
                let structured = hasDigits || part.contains { "@/\\_=:+#<>*%|^~&".contains($0) }
                    || part.dropLast().contains(".")
                chunks.append((NSRange(location: location, length: size), structured))
            }
            // components preserves empty elements, including CR/LF separately.
            location += size + 1
        }
        var codeRanges: [NSRange] = []
        var cursor = 0
        while cursor < length {
            let opening = source.range(of: "`", range: NSRange(location: cursor, length: length - cursor))
            if opening.location == NSNotFound { break }
            var end = NSMaxRange(opening)
            while end < length && source.character(at: end) == 96 { end += 1 }
            let delimiter = String(repeating: "`", count: end - opening.location)
            let closing = source.range(of: delimiter, range: NSRange(location: end, length: length - end))
            if closing.location == NSNotFound {
                codeRanges.append(NSRange(location: opening.location, length: length - opening.location))
                break
            }
            codeRanges.append(NSRange(location: opening.location, length: NSMaxRange(closing) - opening.location))
            cursor = NSMaxRange(closing)
        }
        var chunk = 0
        var codeIndex = 0
        return wordPattern.matches(in: input, range: NSRange(location: 0, length: length)).map { match in
            while chunk + 1 < chunks.count && NSMaxRange(chunks[chunk].0) <= match.range.location { chunk += 1 }
            while codeIndex < codeRanges.count && NSMaxRange(codeRanges[codeIndex]) <= match.range.location { codeIndex += 1 }
            let code = codeIndex < codeRanges.count && codeRanges[codeIndex].location < NSMaxRange(match.range)
            let text = source.substring(with: match.range)
            let key = normalize(text)
            let nonASCII = !key.utf8.allSatisfy { (97...122).contains($0) }
            return Token(range: match.range, text: text, key: key, phone: nonASCII ? "" : VocabularyPhonetics.key(key),
                literal: code || nonASCII || (chunk < chunks.count && chunks[chunk].1))
        }
    }
}
