import Foundation

struct TranscriptionOutputFilter {
    private static let hallucinationPatterns = [
        #"\[.*?\]"#,  // []
        #"\(.*?\)"#,  // ()
        #"\{.*?\}"#,  // {}
    ]

    static func filter(_ text: String, language: String? = nil) -> String {
        var filteredText = text

        // Remove <TAG>...</TAG> blocks
        let tagBlockPattern = #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#
        if let regex = try? NSRegularExpression(pattern: tagBlockPattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        // Remove bracketed hallucinations
        for pattern in hallucinationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(
                    in: filteredText, options: [], range: range, withTemplate: "")
            }
        }

        filteredText = FillerWordCleanup.remove(
            from: filteredText, fillers: FillerWordManager.shared.fillerWords, language: language
        )

        // Normalize horizontal whitespace without flattening paragraphs or lists.
        filteredText = filteredText.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)

        return filteredText
    }
}

/// Repairs only the gaps left by configured fillers; surviving words keep their original casing.
private enum FillerWordCleanup {
    private static let punctuation: Set<Character> = [",", ".", "!", "?", ":", ";", "…", "。", "！", "？", "।", "॥"]
    private static let openingQuotes: Set<Character> = ["\"", "'", "“", "‘", "«"]
    private static let closingQuotes: Set<Character> = ["\"", "'", "”", "’", "»"]
    private static let sentenceEndings: Set<Character> = ["!", "?", "。", "！", "？", "।", "॥"]
    private static let abbreviations: Set<String> = [
        "dr", "mr", "mrs", "ms", "prof", "sr", "jr", "vs", "etc", "inc", "ltd", "co",
        "e.g", "i.e", "a.m", "p.m", "no", "fig", "st",
    ]

    static func remove(from text: String, fillers: [String], language: String?) -> String {
        guard !fillers.isEmpty, !text.isEmpty else { return text }
        let characters = Array(text)
        let protected = protectedCharacters(in: characters)
        // Regex ranges use UTF-16 offsets. Map once instead of walking the string for every match.
        var offsets = [Int](repeating: -1, count: text.utf16.count + 1)
        var offset = 0
        for (index, character) in characters.enumerated() {
            offsets[offset] = index
            offset += character.utf16.count
        }
        offsets[offset] = characters.count
        var removed = [Bool](repeating: false, count: characters.count)
        for filler in Set(fillers) {
            let words = filler.split(whereSeparator: { $0.isWhitespace })
            guard !words.isEmpty else { continue }
            let phrase = words.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[ \\t]+")
            guard let regex = try? NSRegularExpression(pattern: "\\b\(phrase)\\b", options: .caseInsensitive) else { continue }
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: offset)) { match, _, _ in
                guard let range = match?.range else { return }
                let start = offsets[range.location]
                let end = offsets[NSMaxRange(range)]
                guard start >= 0, end > start, !protected[start..<end].contains(true) else { return }
                // Preserve a literal quoted word, such as: The word is "um".
                if start > 0, end < characters.count,
                    openingQuotes.contains(characters[start - 1]), closingQuotes.contains(characters[end]) { return }
                for index in start..<end { removed[index] = true }
            }
        }
        guard removed.contains(true) else { return text }
        let locale = language.flatMap { $0.isEmpty || $0 == "auto" ? nil : Locale(identifier: $0) }
        var output: [Character] = []
        output.reserveCapacity(characters.count)
        var index = 0
        var capitalizeNext = false
        while index < characters.count {
            guard removed[index] else {
                let character = characters[index]
                if capitalizeNext, !character.isWhitespace, !openingQuotes.contains(character) {
                    if character.isLowercase, canCapitalize(at: index, in: characters, protected: protected) {
                        let letter = String(character)
                        output.append(contentsOf: locale.map { letter.uppercased(with: $0) } ?? letter.uppercased())
                    } else {
                        output.append(character)
                    }
                    capitalizeNext = false
                } else {
                    output.append(character)
                }
                index += 1
                continue
            }

            let sentenceStart = startsSentence(after: output)
            var end = index
            var marks: [Character] = []
            var newlines: [Character] = []
            var wasFiller = false
            while end < characters.count {
                let character = characters[end]
                if removed[end] {
                    if !wasFiller { marks.removeAll(keepingCapacity: true) }
                    wasFiller = true
                } else if character.isWhitespace {
                    if character.isNewline { newlines.append(character) }
                    wasFiller = false
                } else if punctuation.contains(character) {
                    // A comma attached directly to a filler belongs to that hesitation.
                    if character != "," || end == 0 || !removed[end - 1] { marks.append(character) }
                    wasFiller = false
                } else {
                    break
                }
                end += 1
            }
            var afterQuotes = end
            while afterQuotes < characters.count,
                closingQuotes.contains(characters[afterQuotes]) || characters[afterQuotes].isWhitespace {
                afterQuotes += 1
            }
            let atEnd = afterQuotes == characters.count
            var nextContent = end
            while nextContent < characters.count,
                openingQuotes.contains(characters[nextContent]) || characters[nextContent].isWhitespace {
                nextContent += 1
            }
            let nextIsUppercase = nextContent < characters.count && characters[nextContent].isUppercase
            if sentenceStart {
                marks.removeAll()
            } else if marks.allSatisfy({ $0 == "." || $0 == "…" }), !atEnd, !nextIsUppercase {
                // A mid-sentence "um. think" is ambiguous; do not invent a sentence boundary.
                marks.removeAll()
            } else if atEnd, marks.allSatisfy({ $0 == "," }) {
                marks.removeAll()
            }
            while let last = output.last, last.isWhitespace && !last.isNewline { output.removeLast() }
            if atEnd || !marks.isEmpty {
                while output.last == "," {
                    output.removeLast()
                    while let last = output.last, last.isWhitespace && !last.isNewline { output.removeLast() }
                }
            }
            output.append(contentsOf: marks)
            if !newlines.isEmpty {
                output.append(contentsOf: newlines)
            } else if !atEnd, let last = output.last,
                !last.isNewline, !openingQuotes.contains(last),
                !closingQuotes.contains(characters[end]) {
                output.append(" ")
            }
            capitalizeNext = sentenceStart || marks.last.map { sentenceEndings.contains($0) } == true
                || newlines.count >= 2
                || (!newlines.isEmpty && output.dropLast(newlines.count).last == ":")
            index = end
        }
        return String(output)
    }

    private static func canCapitalize(at index: Int, in characters: [Character], protected: [Bool]) -> Bool {
        guard !protected[index] else { return false }
        var end = index
        while end < characters.count,
            characters[end].isLetter || characters[end].isNumber || characters[end] == "_" {
            end += 1
        }
        let word = characters[index..<end]
        // Preserve iOS, eBay, camelCase, x86, and snake_case, including all remaining letters.
        if word.contains("_") || word.dropFirst().contains(where: { $0.isUppercase || $0.isNumber }) { return false }
        if word.count == 1, let letter = word.first, ("b"..."z").contains(letter), letter != "i" { return false }
        return true
    }

    private static func startsSentence(after output: [Character]) -> Bool {
        var end = output.count
        var newlines = 0
        let lowerBound = max(0, output.count - 96)
        while end > lowerBound, output[end - 1].isWhitespace || openingQuotes.contains(output[end - 1]) || closingQuotes.contains(output[end - 1]) {
            if output[end - 1].isNewline { newlines += 1 }
            end -= 1
        }
        guard end > 0 else { return true }
        if newlines >= 2 || (newlines > 0 && output[end - 1] == ":") { return true }
        guard end > lowerBound else { return false }
        // Look back at most 96 characters. Long transcripts never cause repeated prefix scans.
        let start = max(0, end - 96)
        let context = String(output[start..<end])
        let line = context.split(whereSeparator: { $0.isNewline }).last.map(String.init) ?? context
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if ["-", "*", "•"].contains(trimmedLine)
            || trimmedLine.range(of: #"^\d+[.)]$"#, options: .regularExpression) != nil { return true }
        if sentenceEndings.contains(output[end - 1]) { return true }
        guard output[end - 1] == ".", end < 2 || output[end - 2] != "." else { return false }
        let token = context.dropLast().split(whereSeparator: { $0.isWhitespace || openingQuotes.contains($0) }).last.map(String.init) ?? ""
        if abbreviations.contains(token.lowercased()) || token.last?.isNumber == true { return false }
        let initials = token.split(separator: ".")
        if !initials.isEmpty, initials.allSatisfy({ $0.count == 1 && $0.first?.isLetter == true }) { return false }
        return true
    }

    private static func protectedCharacters(in characters: [Character]) -> [Bool] {
        var protected = [Bool](repeating: false, count: characters.count)
        var codeDelimiter: Int?
        var index = 0
        while index < characters.count {
            if characters[index] == "`" {
                var end = index + 1
                while end < characters.count, characters[end] == "`" { end += 1 }
                let length = end - index
                if codeDelimiter == length { codeDelimiter = nil }
                else if codeDelimiter == nil { codeDelimiter = length }
                for position in index..<end { protected[position] = true }
                index = end
            } else {
                if codeDelimiter != nil { protected[index] = true }
                index += 1
            }
        }
        var start = 0
        let delimiters: Set<Character> = [",", "!", "?", ";", "\"", "'", "“", "”", "‘", "’", "«", "»"]
        while start < characters.count {
            if characters[start].isWhitespace || delimiters.contains(characters[start]) { start += 1; continue }
            var end = start + 1
            while end < characters.count, !characters[end].isWhitespace, !delimiters.contains(characters[end]) { end += 1 }
            let token = characters[start..<end]
            let structured = token.contains("@") || token.contains("/") || token.contains("\\")
                || (start..<max(start, end - 1)).contains(where: {
                    characters[$0] == "." && $0 > start && characters[$0 - 1].isLetter
                        && (characters[$0 + 1].isLetter || characters[$0 + 1].isNumber)
                })
            if structured { for index in start..<end { protected[index] = true } }
            start = end
        }
        return protected
    }
}
