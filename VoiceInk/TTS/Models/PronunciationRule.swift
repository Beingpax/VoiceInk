import Foundation

enum PronunciationScope: Equatable, Codable, Hashable {
    case global
    case provider(TTSProviderType)

    var displayName: String {
        switch self {
        case .global:
            return "All Providers"
        case .provider(let provider):
            return provider.displayName
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case provider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "global":
            self = .global
        case "provider":
            let providerRaw = try container.decode(String.self, forKey: .provider)
            guard let provider = TTSProviderType(rawValue: providerRaw) else {
                self = .global
                return
            }
            self = .provider(provider)
        default:
            self = .global
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .global:
            try container.encode("global", forKey: .type)
        case .provider(let provider):
            try container.encode("provider", forKey: .type)
            try container.encode(provider.rawValue, forKey: .provider)
        }
    }
}

struct PronunciationRule: Identifiable, Codable, Equatable {
    let id: UUID
    var displayText: String
    var replacementText: String
    var scope: PronunciationScope

    init(id: UUID = UUID(), displayText: String, replacementText: String, scope: PronunciationScope = .global) {
        self.id = id
        self.displayText = displayText
        self.replacementText = replacementText
        self.scope = scope
    }

    func applies(to provider: TTSProviderType) -> Bool {
        switch scope {
        case .global:
            return true
        case .provider(let scopedProvider):
            return scopedProvider == provider
        }
    }
}
