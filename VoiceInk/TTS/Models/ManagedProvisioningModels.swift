import Foundation

struct ManagedAccountSnapshot: Decodable {
    let userId: String
    let planTier: String
    let billingStatus: String
    let premiumExpiresAt: Date?
    let usage: UsageSnapshot?

    struct UsageSnapshot: Decodable {
        let monthTokensUsed: Int
        let monthlyAllowance: Int
        let lastUpdated: Date

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            monthTokensUsed = try container.decodeIfPresent(Int.self, forKey: .monthTokensUsed) ?? 0
            monthlyAllowance = try container.decodeIfPresent(Int.self, forKey: .monthlyAllowance) ?? 0
            if let timestamp = try container.decodeIfPresent(Double.self, forKey: .lastUpdated) {
                lastUpdated = Date(timeIntervalSince1970: timestamp / 1000)
            } else {
                lastUpdated = Date()
            }
        }

        private enum CodingKeys: String, CodingKey {
            case monthTokensUsed
            case monthlyAllowance
            case lastUpdated
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        planTier = try container.decodeIfPresent(String.self, forKey: .planTier) ?? "free"
        billingStatus = try container.decodeIfPresent(String.self, forKey: .billingStatus) ?? "free"
        if let timestamp = try container.decodeIfPresent(Double.self, forKey: .premiumExpiresAt) {
            premiumExpiresAt = Date(timeIntervalSince1970: timestamp / 1000)
        } else {
            premiumExpiresAt = nil
        }
        usage = try container.decodeIfPresent(UsageSnapshot.self, forKey: .usage)
    }

    private enum CodingKeys: String, CodingKey {
        case userId
        case planTier
        case billingStatus
        case premiumExpiresAt
        case usage
    }
}

struct ManagedCredential: Decodable {
    let credentialId: String
    let token: String
    let expiresAt: Date
    let providerReference: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        credentialId = try container.decode(String.self, forKey: .credentialId)
        token = try container.decode(String.self, forKey: .token)
        providerReference = try container.decodeIfPresent(String.self, forKey: .providerReference)
        let expiryValue = try container.decode(Double.self, forKey: .expiresAt)
        expiresAt = Date(timeIntervalSince1970: expiryValue / 1000)
    }

    private enum CodingKeys: String, CodingKey {
        case credentialId
        case token
        case expiresAt
        case providerReference
    }
}
