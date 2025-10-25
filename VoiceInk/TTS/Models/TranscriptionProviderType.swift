import Foundation

enum TranscriptionProviderType: String, CaseIterable, Codable {
    case openAI = "OpenAI"
    case googleChirp2 = "Google Chirp 2"

    var displayName: String { rawValue }

    var systemImageName: String {
        switch self {
        case .openAI:
            return "cpu"
        case .googleChirp2:
            return "cloud"
        }
    }
}
