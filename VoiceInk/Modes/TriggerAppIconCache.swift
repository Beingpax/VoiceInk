import AppKit

final class TriggerAppIconCache {
    static let shared = TriggerAppIconCache()

    private let icons = NSCache<NSString, NSImage>()

    private init() {}

    func icon(for bundleId: String) -> NSImage? {
        let key = bundleId as NSString

        if let icon = icons.object(forKey: key) {
            return icon
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        store(icon, for: bundleId)
        return icon
    }

    func store(_ icon: NSImage, for bundleId: String) {
        icons.setObject(icon, forKey: bundleId as NSString)
    }
}
