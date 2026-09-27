import Foundation

enum VoiceInkPersistence {
    static let productionDirectoryName = "com.prakashjoshipax.VoiceInk"

    static func directoryName(bundleIdentifier: String?, isLocalBuild: Bool) -> String {
        if isLocalBuild {
            return "\(productionDirectoryName).local"
        }
        return bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(productionDirectoryName).unidentified"
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
