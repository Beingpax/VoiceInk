import NaturalLanguage

struct WordCounter {
    static func count(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).count
    }
}
