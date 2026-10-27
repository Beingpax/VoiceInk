import Foundation
import NaturalLanguage
import os

enum VocabularyCorrectionSettings {
    static let isEnabledKey = "IsAutomaticVocabularyCorrectionEnabled"

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: isEnabledKey) == nil || defaults.bool(forKey: isEnabledKey)
    }
}

/// An immutable vocabulary snapshot for a transcription or enhancement request.
struct RecordingVocabulary: Sendable {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VocabularyCorrection")

    let terms: [String]

    init(savedTerms: [String] = [], screenNames: [String] = []) {
        var seen = Set<String>()
        // Saved spellings win collisions and retain priority when providers limit hints.
        terms = (savedTerms + screenNames).compactMap { value in
            let term = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            let key = term.precomposedStringWithCanonicalMapping.lowercased()
            guard !term.isEmpty, seen.insert(key).inserted else { return nil }
            return term
        }
    }

    var enhancementSection: String {
        guard !terms.isEmpty else { return "" }
        let entries = terms.map {
            $0.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }.joined(separator: "\n")
        return """
        Use these entries as preferred spellings for clearly matching words, names, and phonetic transcription mistakes.
        <CUSTOM_VOCABULARY>
        Important Vocabulary:
        \(entries)
        </CUSTOM_VOCABULARY>
        """
    }

    /// Correct the final model output off the main actor using this run's prepared terms.
    func correctTranscription(_ text: String) async throws -> String {
        try Task.checkCancellation()
        guard VocabularyCorrectionSettings.isEnabled, !terms.isEmpty, !text.isEmpty else { return text }
        let vocabulary = terms
        let correction = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let started = Date()
            let output = PhoneticVocabularyMatcher(vocabulary: vocabulary).correct(text)
            try Task.checkCancellation()
            Self.logger.debug(
                "Phonetic correction changed=\(output != text, privacy: .public) terms=\(vocabulary.count, privacy: .public) elapsed=\(Date().timeIntervalSince(started), format: .fixed(precision: 3), privacy: .public)s"
            )
            return output
        }
        let output = try await withTaskCancellationHandler {
            try await correction.value
        } onCancel: {
            correction.cancel()
        }
        try Task.checkCancellation()
        return output
    }

    /// Uses only the system name tagger; no downloaded model or custom name rules.
    static func screenNames(in text: String, language: String?) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        if let language, !language.isEmpty, language != "auto",
            let code = Locale(identifier: language).language.languageCode?.identifier
        {
            let tagLanguage = NLLanguage(rawValue: code)
            if NLTagger.availableTagSchemes(for: .word, language: tagLanguage).contains(.nameType) {
                tagger.setLanguage(tagLanguage, range: text.startIndex..<text.endIndex)
            }
        }
        var names: [String] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            guard !Task.isCancelled else { return false }
            if tag == .personalName || tag == .organizationName || tag == .placeName {
                names.append(String(text[range]))
            }
            return true
        }
        return names
    }
}
