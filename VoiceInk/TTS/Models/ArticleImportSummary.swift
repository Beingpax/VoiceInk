import Foundation

struct ArticleImportSummary: Equatable {
    let sourceURL: URL
    let originalText: String
    let originalWordCount: Int
    var condensedText: String?
    var condensedWordCount: Int?
    var summaryText: String?
    var lastUpdated: Date

    var reductionRatio: Double? {
        guard let condensedWordCount, originalWordCount > 0 else { return nil }
        return Double(condensedWordCount) / Double(originalWordCount)
    }

    var wordSavingsDescription: String? {
        guard let condensedWordCount,
              originalWordCount > 0 else { return nil }
        let saved = originalWordCount - condensedWordCount
        guard saved > 0 else { return nil }
        return "Removes roughly \(saved) words before narration."
    }
}

extension ArticleImportSummary {
    static func make(sourceURL: URL, originalText: String, clock: () -> Date = Date.init) -> ArticleImportSummary {
        ArticleImportSummary(
            sourceURL: sourceURL,
            originalText: originalText,
            originalWordCount: Self.wordCount(in: originalText),
            condensedText: nil,
            condensedWordCount: nil,
            summaryText: nil,
            lastUpdated: clock()
        )
    }

    static func wordCount(in text: String) -> Int {
        let components = text.split { $0.isWhitespace || $0.isNewline }
        return components.count
    }
}
