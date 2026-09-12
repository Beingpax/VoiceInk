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

    /// Detects cycles after replacing existing rules that share a source with
    /// `newSources`; `records` may therefore be passed without pre-filtering.
    static func wouldCreateCycle(
        newSources: [(source: String, destination: String)],
        in records: [(originalText: String, replacementText: String)]
    ) -> Bool {
        var graph: [String: String] = [:]
        for record in records {
            let next = key(for: record.replacementText)
            guard !next.isEmpty else { continue }

            for variant in parse(record.originalText) {
                let variantKey = key(for: variant)
                guard !variantKey.isEmpty, graph[variantKey] == nil else { continue }
                graph[variantKey] = next
            }
        }

        var mutatedKeys = Set<String>()
        for newSource in newSources {
            let sourceKey = key(for: newSource.source)
            let destinationKey = key(for: newSource.destination)
            guard !sourceKey.isEmpty, !destinationKey.isEmpty else { continue }
            graph[sourceKey] = destinationKey
            mutatedKeys.insert(sourceKey)
        }
        guard !mutatedKeys.isEmpty else { return false }

        for sourceKey in mutatedKeys {
            var visited = Set<String>()
            var current = graph[sourceKey] ?? ""
            while !current.isEmpty, visited.insert(current).inserted {
                if mutatedKeys.contains(current) { return true }
                guard let next = graph[current] else { break }
                if next == current { break }
                current = next
            }
        }
        return false
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
