import AppKit
import Foundation

typealias InstalledAppInfo = (url: URL, name: String, bundleId: String, icon: NSImage)

enum InstalledApps {
    static func load() -> [InstalledAppInfo] {
        let appDirectories =
            FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
            + FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
            + FileManager.default.urls(for: .applicationDirectory, in: .systemDomainMask)

        let appURLs = applicationURLs(in: appDirectories)

        let apps: [InstalledAppInfo] = appURLs.compactMap { url in
            guard let bundle = Bundle(url: url),
                let bundleId = bundle.bundleIdentifier,
                let name = (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            else {
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

    static func applicationURLs(
        in appDirectories: [URL],
        fileManager: FileManager = .default
    ) -> [URL] {
        var appURLs: [URL] = []
        var seenPaths = Set<String>()

        for appDirectory in appDirectories {
            guard
                let enumerator = fileManager.enumerator(
                    at: appDirectory,
                    includingPropertiesForKeys: [.isApplicationKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
            else {
                continue
            }

            for item in enumerator {
                guard let url = item as? URL else { continue }
                let values = try? url.resourceValues(forKeys: [.isApplicationKey, .isSymbolicLinkKey])

                if values?.isSymbolicLink == true {
                    enumerator.skipDescendants()

                    let resolvedURL = url.resolvingSymlinksInPath()
                    guard resolvedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                        continue
                    }

                    let path = resolvedURL.standardizedFileURL.path
                    if seenPaths.insert(path).inserted {
                        appURLs.append(resolvedURL)
                    }
                    continue
                }

                guard
                    values?.isApplication == true
                        || url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
                else {
                    continue
                }

                enumerator.skipDescendants()
                let path = url.standardizedFileURL.path
                if seenPaths.insert(path).inserted {
                    appURLs.append(url)
                }
            }
        }

        return appURLs
    }
}
