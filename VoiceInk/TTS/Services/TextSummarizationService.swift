import Foundation

struct SummarizationResult: Equatable {
    let condensedArticle: String
    let summary: String
}

@MainActor
protocol TextSummarizationService {
    func hasCredentials() -> Bool
    func summarize(text: String, sourceURL: URL?) async throws -> SummarizationResult
}
