import Foundation

struct MeetingSummary: Equatable, Sendable {
    let title: String
    let subtitle: String
    let tldr: String
    let keyPoints: [String]
    let actionItems: [String]
}

enum MeetingSummaryError: Error {
    case notConfigured
    case requestFailed(String)
    case invalidResponse(String)
}

@MainActor
protocol MeetingSummarizer {
    func summarize(transcript: String) async throws -> MeetingSummary
    var isConfigured: Bool { get }
    var providerDisplayName: String { get }
}
