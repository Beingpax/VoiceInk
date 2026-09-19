import Foundation

enum VoiceInkPersistence {
    static let productionDirectoryName = "com.prakashjoshipax.VoiceInk"

    static func directoryName(bundleIdentifier: String?, isLocalBuild: Bool) -> String {
        if isLocalBuild {
            return "\(productionDirectoryName).local"
        }
        if bundleIdentifier == "\(productionDirectoryName).dev" {
            return "\(productionDirectoryName).dev"
        }
        return productionDirectoryName
    }

    static var directoryURL: URL {
        #if LOCAL_BUILD
            let isLocalBuild = true
        #else
            let isLocalBuild = false
        #endif

        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(
                directoryName(bundleIdentifier: Bundle.main.bundleIdentifier, isLocalBuild: isLocalBuild),
                isDirectory: true
            )
    }
}
