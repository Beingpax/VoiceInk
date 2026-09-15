import Foundation

enum WordReplacementVariants {
    struct CycleDetector {
        private var graph: [String: Set<String>] = [:]

        init(records: [(originalText: String, replacementText: String)]) {
            for record in records {
                let destination = WordReplacementVariants.key(for: record.replacementText)
                guard !destination.isEmpty else { continue }

                for source in WordReplacementVariants.parse(record.originalText) {
                    let sourceKey = WordReplacementVariants.key(for: source)
                    guard !sourceKey.isEmpty else { continue }
                    graph[sourceKey, default: []].insert(destination)
                }
            }
        }

        /// Adds or replaces one source edge when it does not introduce a cycle.
        /// Rejected edges leave the graph unchanged.
        mutating func insertIfAcyclic(source: String, destination: String) -> Bool {
            let sourceKey = WordReplacementVariants.key(for: source)
            let destinationKey = WordReplacementVariants.key(for: destination)
            guard !sourceKey.isEmpty, !destinationKey.isEmpty else { return false }

            let previousDestinations = graph[sourceKey]
            graph[sourceKey] = [destinationKey]

            guard !canReach(sourceKey, from: destinationKey) else {
                graph[sourceKey] = previousDestinations
                return false
            }
            return true
        }

        private func canReach(_ target: String, from start: String) -> Bool {
            var pending = [start]
            var visited = Set<String>()

            while let node = pending.popLast() {
                guard visited.insert(node).inserted else { continue }
                if node == target { return true }
                pending.append(contentsOf: graph[node] ?? [])
            }
            return false
        }
    }

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
        var detector = CycleDetector(records: records)
        for newSource in newSources {
            if !detector.insertIfAcyclic(
                source: newSource.source,
                destination: newSource.destination
            ) {
                return true
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
