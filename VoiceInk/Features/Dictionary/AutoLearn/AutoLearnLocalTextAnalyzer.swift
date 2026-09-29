import AppKit
import NaturalLanguage

struct AutoLearnLocalTextAnalysis {
    struct Token {
        let range: NSRange
        let text: String
        let lexicalClass: NLTag?
        let lemma: String?
    }

    struct Entity {
        let range: NSRange
        let type: NLTag
    }

    let language: NLLanguage
    let tokens: [Token]
    let entities: [Entity]
}

struct AutoLearnSpellingEvidence {
    let isMisspelled: Bool
    let suggestions: [String]
}

@MainActor
protocol AutoLearnLocalTextAnalyzing {
    func analyze(_ text: String, languageHint: String?) -> AutoLearnLocalTextAnalysis?
    func spelling(for text: String, language: NLLanguage) -> AutoLearnSpellingEvidence?
}

/// Apple's installed language assets only. This never requests assets, learns
/// system spelling, or calls an LLM. Unsupported languages fail closed.
@MainActor
final class AutoLearnLocalTextAnalyzer: AutoLearnLocalTextAnalyzing {
    func analyze(_ text: String, languageHint: String?) -> AutoLearnLocalTextAnalysis? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let detected = hypotheses.max { $0.value < $1.value }
        let hint = languageHint?.replacingOccurrences(of: "_", with: "-")
        let hintedLanguage = hint.flatMap { code -> NLLanguage? in
            guard code != "auto", !code.isEmpty else { return nil }
            return NLLanguage(rawValue: code.components(separatedBy: "-")[0])
        }
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        let language: NLLanguage
        if let hintedLanguage {
            // A configured English default must not make non-English dictation
            // look like a collection of misspelled English words.
            if wordCount >= 4, let detected, detected.value >= 0.9,
                detected.key != hintedLanguage {
                return nil
            }
            language = hintedLanguage
        } else {
            guard wordCount >= 4, let detected, detected.value >= 0.8 else { return nil }
            language = detected.key
        }

        let available = NLTagger.availableTagSchemes(for: .word, language: language)
        guard available.contains(.lexicalClass), available.contains(.lemma) else { return nil }
        let schemes: [NLTagScheme] = available.contains(.nameType)
            ? [.nameType, .lexicalClass, .lemma] : [.lexicalClass, .lemma]
        let tagger = NLTagger(tagSchemes: schemes)
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        tagger.setLanguage(language, range: range)

        var tokens: [AutoLearnLocalTextAnalysis.Token] = []
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]) { tag, tokenRange in
            let lemma = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0
            tokens.append(.init(range: NSRange(tokenRange, in: text),
                text: String(text[tokenRange]), lexicalClass: tag, lemma: lemma?.rawValue))
            return true
        }

        var entities: [AutoLearnLocalTextAnalysis.Entity] = []
        if schemes.contains(.nameType) {
            tagger.enumerateTags(in: range, unit: .word, scheme: .nameType,
                options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, entityRange in
                if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                    entities.append(.init(range: NSRange(entityRange, in: text), type: tag))
                }
                return true
            }
        }
        return .init(language: language, tokens: tokens, entities: entities)
    }

    func spelling(for text: String, language: NLLanguage) -> AutoLearnSpellingEvidence? {
        let checker = NSSpellChecker.shared
        let code = language.rawValue
        guard let spellingLanguage = checker.availableLanguages.first(where: { $0 == code })
            ?? checker.availableLanguages.first(where: { $0.hasPrefix(code + "_") })
        else { return nil }
        let document = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: document) }
        let misspelling = checker.checkSpelling(of: text, startingAt: 0,
            language: spellingLanguage, wrap: false, inSpellDocumentWithTag: document, wordCount: nil)
        let suggestions = checker.guesses(forWordRange: NSRange(location: 0, length: text.utf16.count),
            in: text, language: spellingLanguage, inSpellDocumentWithTag: document) ?? []
        return .init(isMisspelled: misspelling.location != NSNotFound,
            suggestions: Array(suggestions.prefix(5)))
    }
}
