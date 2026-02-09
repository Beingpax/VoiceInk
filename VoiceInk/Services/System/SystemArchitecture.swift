import Foundation

enum SystemArchitecture {
    static var isIntelMac: Bool {
        #if arch(x86_64)
        return true
        #else
        return false
        #endif
    }

    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    static var current: String {
        #if arch(arm64)
        return "Apple Silicon (ARM64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }
}
