import Foundation

enum VocabularyBiasingPrompt {
    static func build(existing: String? = nil, vocabulary: [String]) -> String {
        var seen = Set<String>()
        var terms: [String] = []
        for term in vocabulary {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                terms.append(trimmed)
            }
            if terms.count >= 200 { break }
        }

        var segments: [String] = []
        if let existing = existing?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            segments.append(existing)
        }
        if !terms.isEmpty {
            segments.append(
                "The audio may reference the following names, products, and technical terms — "
                    + "transcribe any occurrences using these exact spellings: "
                    + terms.joined(separator: ", ") + ".")
        }
        return segments.joined(separator: " ")
    }
}
