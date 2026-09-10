import Foundation

enum VocabularySortMode: String, CaseIterable {
    case wordAsc = "wordAsc"
    case wordDesc = "wordDesc"
    case newest = "newest"
    case oldest = "oldest"
}

enum WordReplacementSortMode: String, CaseIterable {
    case originalAsc = "originalAsc"
    case originalDesc = "originalDesc"
    case replacementAsc = "replacementAsc"
    case replacementDesc = "replacementDesc"
    case newest = "newest"
    case oldest = "oldest"
}

final class DictionarySortService {
    static let shared = DictionarySortService()

    private enum PreferenceKey {
        static let vocabulary = "vocabularySortMode"
        static let wordReplacement = "wordReplacementSortMode"
    }

    private init() {}

    func savedVocabularyMode(defaults: UserDefaults = .standard) -> VocabularySortMode {
        guard let rawValue = defaults.string(forKey: PreferenceKey.vocabulary),
            let mode = VocabularySortMode(rawValue: rawValue)
        else {
            return .wordAsc
        }
        return mode
    }

    func nextVocabularyMode(after mode: VocabularySortMode) -> VocabularySortMode {
        nextMode(after: mode, in: VocabularySortMode.allCases)
    }

    func saveVocabularyMode(_ mode: VocabularySortMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: PreferenceKey.vocabulary)
    }

    func sortVocabulary(_ words: [VocabularyWord], by mode: VocabularySortMode) -> [VocabularyWord] {
        switch mode {
        case .wordAsc:
            return words.sorted { compareWords($0, $1, ascending: true) }
        case .wordDesc:
            return words.sorted { compareWords($0, $1, ascending: false) }
        case .newest:
            return words.sorted { compareDates($0, $1, newestFirst: true) }
        case .oldest:
            return words.sorted { compareDates($0, $1, newestFirst: false) }
        }
    }

    func savedWordReplacementMode(defaults: UserDefaults = .standard) -> WordReplacementSortMode {
        guard let rawValue = defaults.string(forKey: PreferenceKey.wordReplacement),
            let mode = WordReplacementSortMode(rawValue: rawValue)
        else {
            return .originalAsc
        }
        return mode
    }

    func nextWordReplacementMode(after mode: WordReplacementSortMode) -> WordReplacementSortMode {
        nextMode(after: mode, in: WordReplacementSortMode.allCases)
    }

    func saveWordReplacementMode(_ mode: WordReplacementSortMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: PreferenceKey.wordReplacement)
    }

    func sortWordReplacements(
        _ replacements: [WordReplacement],
        by mode: WordReplacementSortMode
    ) -> [WordReplacement] {
        switch mode {
        case .originalAsc:
            return replacements.sorted { compareText($0, $1, keyPath: \.originalText, ascending: true) }
        case .originalDesc:
            return replacements.sorted { compareText($0, $1, keyPath: \.originalText, ascending: false) }
        case .replacementAsc:
            return replacements.sorted { compareText($0, $1, keyPath: \.replacementText, ascending: true) }
        case .replacementDesc:
            return replacements.sorted { compareText($0, $1, keyPath: \.replacementText, ascending: false) }
        case .newest:
            return replacements.sorted { compareDates($0, $1, newestFirst: true) }
        case .oldest:
            return replacements.sorted { compareDates($0, $1, newestFirst: false) }
        }
    }

    private func nextMode<Mode: Equatable>(after mode: Mode, in modes: [Mode]) -> Mode {
        guard !modes.isEmpty else { return mode }
        let currentIndex = modes.firstIndex(of: mode) ?? 0
        return modes[(currentIndex + 1) % modes.count]
    }

    private func compareWords(_ lhs: VocabularyWord, _ rhs: VocabularyWord, ascending: Bool) -> Bool {
        let comparison = lhs.word.localizedCaseInsensitiveCompare(rhs.word)
        if comparison != .orderedSame {
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded < rhs.dateAdded }
        return lhs.word.compare(rhs.word) == .orderedAscending
    }

    private func compareDates(_ lhs: VocabularyWord, _ rhs: VocabularyWord, newestFirst: Bool) -> Bool {
        if lhs.dateAdded != rhs.dateAdded {
            return newestFirst ? lhs.dateAdded > rhs.dateAdded : lhs.dateAdded < rhs.dateAdded
        }
        let comparison = lhs.word.localizedCaseInsensitiveCompare(rhs.word)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.word.compare(rhs.word) == .orderedAscending
    }

    private func compareText(
        _ lhs: WordReplacement,
        _ rhs: WordReplacement,
        keyPath: KeyPath<WordReplacement, String>,
        ascending: Bool
    ) -> Bool {
        let comparison = lhs[keyPath: keyPath].localizedCaseInsensitiveCompare(rhs[keyPath: keyPath])
        if comparison != .orderedSame {
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded < rhs.dateAdded }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func compareDates(_ lhs: WordReplacement, _ rhs: WordReplacement, newestFirst: Bool) -> Bool {
        if lhs.dateAdded != rhs.dateAdded {
            return newestFirst ? lhs.dateAdded > rhs.dateAdded : lhs.dateAdded < rhs.dateAdded
        }
        let comparison = lhs.originalText.localizedCaseInsensitiveCompare(rhs.originalText)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
