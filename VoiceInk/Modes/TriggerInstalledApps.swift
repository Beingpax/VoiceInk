import AppKit
import Foundation

typealias InstalledAppInfo = (url: URL, name: String, bundleId: String, icon: NSImage)

enum InstalledApps {
    static func load() -> [InstalledAppInfo] {
        let appDirectories = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask) +
            FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask) +
            FileManager.default.urls(for: .applicationDirectory, in: .systemDomainMask)

        var appURLs: [URL] = []

        func scanDirectory(_ baseURL: URL, depth: Int = 0) {
            guard depth < 5,
                  let enumerator = FileManager.default.enumerator(
                    at: baseURL,
                    includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                  ) else { return }

            for item in enumerator {
                guard let url = item as? URL else { continue }
                let resolvedURL = url.resolvingSymlinksInPath()

                if resolvedURL.pathExtension == "app" {
                    appURLs.append(resolvedURL)
                    enumerator.skipDescendants()
                    continue
                }

                var isDirectory: ObjCBool = false
                if url != resolvedURL,
                   FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    enumerator.skipDescendants()
                    scanDirectory(resolvedURL, depth: depth + 1)
                }
            }
        }

        for appDirectory in appDirectories {
            scanDirectory(appDirectory)
        }

        let apps: [InstalledAppInfo] = appURLs.compactMap { url in
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier,
                  let name = (bundle.infoDictionary?["CFBundleName"] as? String) ??
                    (bundle.infoDictionary?["CFBundleDisplayName"] as? String) else {
                return nil
            }

            let icon = NSWorkspace.shared.icon(forFile: url.path)
            TriggerAppIconCache.shared.store(icon, for: bundleId)

            return (url: url, name: name, bundleId: bundleId, icon: icon)
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        var seenBundleIds = Set<String>()
        return apps.filter { seenBundleIds.insert($0.bundleId).inserted }
    }
}
