import Foundation

enum AppleIntelligenceModel: String, CaseIterable, Identifiable, Sendable {
    case onDevice = "On-Device"
    case privateCloudCompute = "Private Cloud Compute"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice:
            return String(localized: "On-Device")
        case .privateCloudCompute:
            return String(localized: "Private Cloud Compute")
        }
    }

    func pickerTitle(onDeviceVariantName: String?) -> String {
        switch self {
        case .onDevice:
            if let onDeviceVariantName, !onDeviceVariantName.isEmpty {
                return String(localized: "On-Device (\(onDeviceVariantName))")
            }
            return displayName
        case .privateCloudCompute:
            return displayName
        }
    }

    var detail: String {
        switch self {
        case .onDevice:
            return String(
                localized: "Apple has two on-device models: AFM 3 Core and AFM 3 Core Advanced. This Mac picks one automatically (Advanced on M3 or later with enough memory). Apps cannot choose the other one. The router Siri mentioned is inside Core Advanced, not a third model VoiceInk can call."
            )
        case .privateCloudCompute:
            return String(
                localized: "Apple’s server model. Needs Apple’s Private Cloud Compute entitlement on a Developer ID or App Store build. This local ad-hoc build can see PCC as available, then Apple rejects the request."
            )
        }
    }

    var isCallableWithCurrentSDK: Bool {
        switch self {
        case .onDevice:
            return true
        case .privateCloudCompute:
            return AppleIntelligenceCloudSupport.isCallableWithCurrentSDK
        }
    }

    static var preferredDefault: AppleIntelligenceModel {
        .onDevice
    }

    static let privateCloudComputeEntitlementMessage = String(
        localized: "Private Cloud Compute needs a signed VoiceInk build with Apple’s PCC entitlement. This local ad-hoc build cannot use it. Switch the Mode to On-Device."
    )

    static func resolved(from modelName: String?) -> AppleIntelligenceModel {
        guard let modelName, let model = AppleIntelligenceModel(rawValue: modelName) else {
            return preferredDefault
        }
        return model
    }
}

struct AppleIntelligenceEnhanceResult: Sendable {
    let text: String
    let modelLabel: String
}

enum AppleIntelligenceLimits {
    static let requestTimeout: TimeInterval = 90
}

enum AppleIntelligenceCloudSupport {
    static var isCallableWithCurrentSDK: Bool {
        guard #available(macOS 27, *) else {
            return false
        }

        #if canImport(FoundationModels)
            return true
        #else
            return false
        #endif
    }

    static let unavailableReason = String(
        localized: "Private Cloud Compute needs macOS 27. This Mac or this VoiceInk build cannot call that model."
    )
}

enum AppleIntelligenceOutputSanitizer {
    static func sanitize(_ text: String) -> String {
        var processedText = AIEnhancementOutputFilter.filter(text)

        if processedText.hasPrefix("```") {
            var lines = processedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.first?.hasPrefix("```") == true {
                lines.removeFirst()
            }
            if lines.last?.hasPrefix("```") == true {
                lines.removeLast()
            }
            processedText = lines.joined(separator: "\n")
        }

        if processedText.count >= 2 {
            let first = processedText.first
            let last = processedText.last
            if (first == "\"" && last == "\"") || (first == "“" && last == "”") || (first == "'" && last == "'") {
                processedText = String(processedText.dropFirst().dropLast())
            }
        }

        return processedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
