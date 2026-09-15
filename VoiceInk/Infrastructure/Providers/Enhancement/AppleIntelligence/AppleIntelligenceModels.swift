import Foundation
import Security

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
                localized: "Apple’s server model. Needs Apple’s Private Cloud Compute entitlement on a Developer ID or App Store build, not signing alone."
            )
        }
    }

    var isCallableWithCurrentSDK: Bool {
        switch self {
        case .onDevice:
            return AppleIntelligenceOnDeviceSupport.isCallableWithCurrentSDK
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

enum AppleIntelligenceOnDeviceSupport {
    static var isCallableWithCurrentSDK: Bool {
        guard #available(macOS 26, *) else {
            return false
        }

        #if canImport(FoundationModels)
            return true
        #else
            return false
        #endif
    }
}

enum AppleIntelligenceCloudSupport {
    static var isCallableWithCurrentSDK: Bool {
        guard #available(macOS 27, *) else {
            return false
        }

        #if canImport(FoundationModels)
            return hasPrivateCloudComputeEntitlement
        #else
            return false
        #endif
    }

    static var hasPrivateCloudComputeEntitlement: Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return false
        }

        var signingInformation: CFDictionary?
        let copyStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard copyStatus == errSecSuccess, let signingInformation else {
            return false
        }

        let entitlements = (signingInformation as NSDictionary)[kSecCodeInfoEntitlementsDict] as? [String: Any]
        return entitlements?["com.apple.developer.private-cloud-compute"] as? Bool == true
    }

    static let unavailableReason = String(
        localized: "Private Cloud Compute needs macOS 27 and Apple’s PCC entitlement on a Developer ID or App Store build."
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

        return processedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
