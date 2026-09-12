import Foundation

enum WordReplacementVariants {
    static func parse(_ text: String) -> [String] {
        deduplicated(
            text
                .split(separator: ",")
                .map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .precomposedStringWithCanonicalMapping
                }
                .filter { !$0.isEmpty }
        )
    }

    static func serialize(_ variants: [String]) -> String {
        deduplicated(variants).joined(separator: ", ")
    }

    static func key(for text: String) -> String {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping

        return (normalized as NSString).folding(options: .caseInsensitive, locale: nil)
    }

    static func destinationKey(for text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    static func contains(_ variant: String, in variants: [String]) -> Bool {
        let candidateKey = key(for: variant)
        return variants.contains { key(for: $0) == candidateKey }
    }

    private static func deduplicated(_ variants: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for variant in variants {
            let trimmed = variant.trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
            guard !trimmed.isEmpty else { continue }

            let comparisonKey = key(for: trimmed)
            guard !comparisonKey.isEmpty, seen.insert(comparisonKey).inserted else { continue }
            result.append(trimmed)
        }

        return result
    }
}
