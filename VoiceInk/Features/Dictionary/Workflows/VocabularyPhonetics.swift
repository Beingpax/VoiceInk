import Foundation

/// A small, English-oriented Metaphone-style encoder. These are general
/// grapheme rules, not vocabulary-specific error aliases or a pronunciation
/// dictionary. Codes approximate consonant sounds; they are not IPA or a
/// reliable pronunciation model for every personal name/language.
enum VocabularyPhonetics {
    static func key(_ word: String) -> String {
        let letters = Array(word.lowercased().utf8)
        guard !letters.isEmpty, letters.allSatisfy({ (97...122).contains($0) }) else { return "" }
        let a = letters.map { Character(Unicode.Scalar($0)) }
        func at(_ i: Int) -> Character { a.indices.contains(i) ? a[i] : " " }
        func vowel(_ c: Character) -> Bool { "aeiouy".contains(c) }
        func begins(_ value: String, at index: Int) -> Bool {
            let b = Array(value)
            return index + b.count <= a.count && Array(a[index..<(index + b.count)]) == b
        }
        var i = 0
        var code = ""
        if ["kn", "gn", "pn", "wr", "ae"].contains(String(a.prefix(2))) { i = 1 }
        while i < a.count {
            let c = a[i]
            let previous = at(i - 1)
            let next = at(i + 1)
            if c == previous && c != "c" { i += 1; continue }
            switch c {
            case "a", "e", "i", "o", "u":
                if i == 0 { code += "A" }
            case "b": code += "P"
            case "c":
                if next == "h" {
                    code += begins("chae", at: i) ? "K" : "X"
                    i += 1
                } else if begins("cia", at: i) || begins("cio", at: i) {
                    code += "X"; i += 2
                } else if "eiy".contains(next) {
                    code += "S"
                } else {
                    code += "K"
                    if next == "k" || next == "q" || next == "c" { i += 1 }
                }
            case "d":
                if next == "g" && "eiy".contains(at(i + 2)) {
                    code += "J"; i += 2
                } else { code += "T" }
            case "f": code += "F"
            case "g":
                if next == "n" && i + 2 == a.count {
                    break
                } else if next == "h" {
                    if i > 0 && vowel(previous) && i + 2 < a.count && at(i + 2) == "t" { code += "F" }
                    else if i == 0 { code += at(i + 2) == "i" ? "J" : "K" }
                    i += 1
                } else { code += "eiy".contains(next) ? "J" : "K" }
            case "h":
                if (i == 0 || vowel(previous)) && vowel(next) { code += "H" }
            case "j": code += "J"
            case "k": if previous != "c" { code += "K" }
            case "l": code += "L"
            case "m": code += "M"
            case "n": code += "N"
            case "p":
                if next == "h" { code += "F"; i += 1 } else { code += "P" }
            case "q": code += "K"
            case "r": code += "R"
            case "s":
                if next == "h" { code += "X"; i += 1 }
                else if begins("sio", at: i) || begins("sia", at: i) { code += "X"; i += 2 }
                else if next == "c" {
                    code += "eiy".contains(at(i + 2)) ? "S" : "SK"; i += 1
                } else { code += "S" }
            case "t":
                if next == "h" { code += "0"; i += 1 }
                else if begins("tio", at: i) || begins("tia", at: i) { code += "X"; i += 2 }
                else if !begins("tch", at: i) { code += "T" }
            case "v": code += "F"
            case "w", "y": if vowel(next) { code += String(c).uppercased() }
            case "x": code += i == 0 ? "S" : "KS"
            case "z": code += "S"
            default: break
            }
            i += 1
        }
        return collapse(code)
    }

    static func phraseKey(_ words: [String]) -> String {
        phraseKeyFromCodes(words.map(key))
    }

    /// Reuse word encodings across overlapping spans and vocabulary candidates.
    static func phraseKeyFromCodes(_ codes: [String]) -> String {
        collapse(codes.joined())
    }

    private static func collapse(_ value: String) -> String {
        var result = ""
        for c in value where c != result.last { result.append(c) }
        return result
    }

    /// Weighted sound-code alignment. Related sibilants have a smaller cost;
    /// inserting/deleting a sound always has a full cost. This is a heuristic
    /// distance, not an acoustic probability or a metric-tree distance.
    static func distance(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard !a.isEmpty, !b.isEmpty else { return lhs == rhs ? 0 : 1 }
        var previous = (0...b.count).map(Double.init)
        for i in a.indices {
            var row = [Double](repeating: 0, count: b.count + 1)
            row[0] = Double(i + 1)
            for j in b.indices {
                let x = a[i], y = b[j]
                let substitution: Double
                if x == y { substitution = 0 }
                else if (x == 83 && y == 88) || (x == 88 && y == 83) { substitution = 0.25 }
                else if (x == 74 && y == 88) || (x == 88 && y == 74)
                    || (x == 84 && y == 48) || (x == 48 && y == 84) { substitution = 0.5 }
                else { substitution = 1 }
                row[j + 1] = min(previous[j + 1] + 1, row[j] + 1, previous[j] + substitution)
            }
            previous = row
        }
        return previous[b.count] / Double(max(a.count, b.count))
    }
}
