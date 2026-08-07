import SwiftUI

/// One actionable row in the command palette.
struct CommandPaletteItem: Identifiable {
    enum Kind {
        case destination(ViewType)
        case mode(ModeConfig)
        case transcript(Transcription)
        case action

        var sectionTitle: LocalizedStringKey {
            switch self {
            case .destination: return "Go To"
            case .mode: return "Switch Mode"
            case .transcript: return "History"
            case .action: return "Actions"
            }
        }

        /// Ordering of sections in the results list.
        var rank: Int {
            switch self {
            case .action: return 0
            case .destination: return 1
            case .mode: return 2
            case .transcript: return 3
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let icon: String
    let tint: Color
    let perform: () -> Void

    /// Text the fuzzy matcher scores against.
    var searchableText: String {
        [title, subtitle].compactMap { $0 }.joined(separator: " ")
    }
}

/// Subsequence-based fuzzy matching, the same shape editors use for file pickers: every character
/// of the query must appear in order, and matches that are contiguous or land on word boundaries
/// score higher.
enum CommandPaletteMatcher {
    static func score(query: String, candidate: String) -> Int? {
        let query = query.lowercased().filter { !$0.isWhitespace }
        guard !query.isEmpty else { return 0 }

        let candidate = Array(candidate.lowercased())
        var score = 0
        var candidateIndex = 0
        var previousMatchIndex: Int?

        for character in query {
            var found = false

            while candidateIndex < candidate.count {
                defer { candidateIndex += 1 }

                guard candidate[candidateIndex] == character else { continue }

                if let previous = previousMatchIndex, candidateIndex == previous + 1 {
                    score += 5  // contiguous run
                }
                if candidateIndex == 0 || candidate[candidateIndex - 1] == " " {
                    score += 8  // start of a word
                }
                score += 1

                previousMatchIndex = candidateIndex
                found = true
                break
            }

            guard found else { return nil }
        }

        // Prefer shorter candidates when scores are otherwise close.
        return score - candidate.count / 12
    }

    static func rank(_ items: [CommandPaletteItem], query: String) -> [CommandPaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return items.sorted { $0.kind.rank < $1.kind.rank }
        }

        return
            items
            .compactMap { item -> (CommandPaletteItem, Int)? in
                guard let score = score(query: trimmed, candidate: item.searchableText) else { return nil }
                return (item, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.kind.rank < rhs.0.kind.rank
            }
            .map(\.0)
    }
}
