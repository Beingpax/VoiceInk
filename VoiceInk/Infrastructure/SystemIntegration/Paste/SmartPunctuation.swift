import Foundation

enum SmartPunctuation {
    static let settingsKey = "SmartPunctuationEnabled"
    private static let typography = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

    struct Context: Equatable, Sendable {
        let before: String
        let after: String

        init?(text: String, selection: NSRange) {
            let utf16Length = text.utf16.count
            guard selection.location >= 0, selection.length >= 0,
                selection.location <= utf16Length,
                selection.length <= utf16Length - selection.location,
                let range = Range(selection, in: text),
                NSRange(range, in: text) == selection,
                range.lowerBound == text.endIndex || text.indices.contains(range.lowerBound),
                range.upperBound == text.endIndex || text.indices.contains(range.upperBound)
            else { return nil }
            before = String(text[..<range.lowerBound].suffix(256))
            after = String(text[range.upperBound...].prefix(256))
        }
    }

    /// Changes only the insertion; surrounding text and the saved transcript stay intact.
    static func adjusted(_ text: String, context: Context) -> String {
        guard [text, context.before, context.after].allSatisfy({
            $0.unicodeScalars.allSatisfy { $0.isASCII || typography.contains($0) }
        }) else { return text }
        let core = text.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty, !text.contains(where: { $0.isNewline || $0 == "\t" }),
            !core.contains(where: { "`{}\\".contains($0) }),
            !core.contains("@"), !containsStructuredToken(core) else { return text }
        let before = context.before
        let after = context.after
        if let left = before.last, let right = after.first,
            left.isLetterOrNumber, right.isLetterOrNumber {
            return " " + core + " "
        }

        var result = adjustedCapitalization(core, before: before)
        let following = after.drop(while: \.isWhitespace)
        let sameLine = !after.prefix(while: \.isWhitespace).contains(where: \.isNewline)
        if sameLine, let last = result.last, let next = following.first,
            ".,;:!?。！？".contains(last), last == next,
            !result.hasSuffix(String(repeating: String(last), count: 2)),
            !following.hasPrefix(String(repeating: String(last), count: 2)) {
            result.removeLast()
        } else if sameLine, following.first.map({ ($0.isLetter && !$0.isUppercase) || ",;:!?、，；：！？".contains($0) }) == true,
            canRemovePeriod(from: result) {
            result.removeLast()
        }
        guard !result.isEmpty else { return text }

        // Keep intentional whitespace unless the editor already supplies the boundary.
        var prefix = String(text.prefix(while: { $0.isWhitespace }))
        var suffix = String(text.reversed().prefix(while: { $0.isWhitespace }).reversed())
        if before.last?.isWhitespace == true { prefix = "" }
        if after.first?.isWhitespace == true || after.first.map(isClosingPunctuation) == true { suffix = "" }
        if let left = before.last, let first = result.first {
            if isOpeningPunctuation(left) { prefix = "" }
            else if prefix.isEmpty, needsSpace(between: left, and: first) { prefix = " " }
        }
        if let last = result.last, let right = after.first,
            suffix.isEmpty, needsSpace(between: last, and: right) {
            suffix = " "
        }
        return prefix + result + suffix
    }

    private static func adjustedCapitalization(_ text: String, before: String) -> String {
        guard let first = text.first, first.isLetter else { return text }
        let token = String(text.prefix(while: { $0.isLetter || $0 == "'" || $0 == "’" }))
        guard token.dropFirst().allSatisfy({ !$0.isUppercase }),
            token != "I", !token.hasPrefix("I'"), !token.hasPrefix("I’") else { return text }
        let left = before.trimmingCharacters(in: .whitespaces)
        let startsSentence = left.isEmpty || left.last?.isNewline == true
            || left.last.map { "!?。！？".contains($0) } == true
            || (left.hasSuffix(".") && canRemovePeriod(from: left))
        if startsSentence, first.isLowercase {
            return first.uppercased() + text.dropFirst()
        }
        guard !startsSentence, first.isUppercase,
            let previous = left.last, previous.isLetterOrNumber
        else { return text }

        return first.lowercased() + text.dropFirst()
    }

    private static func canRemovePeriod(from text: String) -> Bool {
        if text.hasSuffix("。") {
            return !text.hasSuffix("。。") && text.dropLast().last?.isLetter == true
        }
        guard text.hasSuffix("."), !text.hasSuffix("..") else { return false }
        let token = text.dropLast().split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        guard token.count > 1, token.allSatisfy(\.isLetter) else { return false }
        return !token.allSatisfy(\.isUppercase)
    }

    private static func needsSpace(between left: Character, and right: Character) -> Bool {
        guard !left.isWhitespace, !right.isWhitespace,
            !isOpeningPunctuation(left), !isClosingPunctuation(right) else { return false }
        return (left.isLetterOrNumber || isClosingPunctuation(left)) && right.isLetterOrNumber
    }

    private static func isOpeningPunctuation(_ character: Character) -> Bool {
        "([{“‘«「『（【".contains(character)
    }

    private static func isClosingPunctuation(_ character: Character) -> Bool {
        ".,;:!?)]}”’»、。，；：！？）」』】".contains(character)
    }

    private static func containsStructuredToken(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).contains {
            $0.contains("/") || String($0).trimmingCharacters(in: .punctuationCharacters).contains(".")
        }
    }
}

private extension Character {
    var isLetterOrNumber: Bool { isLetter || isNumber }
}
