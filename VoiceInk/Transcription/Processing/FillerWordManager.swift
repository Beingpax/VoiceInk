import Foundation

class FillerWordManager: ObservableObject {
    static let shared = FillerWordManager()

    static let defaultFillerWords = [
        "uh", "um", "uhm", "umm", "uhh", "uhhh",
        "hmm", "hm", "mmm", "mm", "mh", "ehh"
    ]

    private let fillerWordsKey = "FillerWords"
    private let removeFillerWordsKey = "RemoveFillerWords"

    @Published var fillerWords: [String] {
        didSet {
            UserDefaults.standard.set(fillerWords, forKey: fillerWordsKey)
            recompileRegexes()
        }
    }

    /// Pre-compiled regexes for filler word removal (avoids recompilation per transcription)
    private(set) var compiledFillerRegexes: [NSRegularExpression] = []

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: removeFillerWordsKey)
    }

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: fillerWordsKey) {
            self.fillerWords = saved
        } else {
            self.fillerWords = Self.defaultFillerWords
        }
        recompileRegexes()
    }

    private func recompileRegexes() {
        compiledFillerRegexes = fillerWords.compactMap { word in
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b[,.]?"
            return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }
    }

    func addWord(_ word: String) -> Bool {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        guard !fillerWords.contains(where: { $0.lowercased() == normalized }) else { return false }
        fillerWords.append(normalized)
        return true
    }

    func removeWord(_ word: String) {
        fillerWords.removeAll { $0.lowercased() == word.lowercased() }
    }

}
