import SwiftUI

struct ModeTriggerSelectionView: View {
    @Binding var appConfigs: [AppConfig]
    @Binding var websiteConfigs: [URLConfig]
    @Binding var triggerGroups: [ModeTriggerGroup]
    @Binding var triggerWords: [String]
    let installedApps: [InstalledAppInfo]
    let cleanURL: (String) -> String
    let loadInstalledAppsIfNeeded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($triggerGroups) { $group in
                TriggerGroupRow(
                    group: $group,
                    installedApps: installedApps,
                    reservedAppBundleIds: reservedAppBundleIds(excluding: group.id),
                    reservedWebsites: reservedWebsites(excluding: group.id),
                    cleanURL: cleanURL,
                    loadInstalledAppsIfNeeded: loadInstalledAppsIfNeeded
                ) {
                    triggerGroups.removeAll { $0.id == group.id }
                }
            }

            if !appConfigs.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 38), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(appConfigs) { appConfig in
                        TriggerAppChip(appConfig: appConfig) {
                            appConfigs.removeAll { $0.id == appConfig.id }
                        }
                    }
                }
            }

            if !websiteConfigs.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(websiteConfigs) { urlConfig in
                        TriggerWebsiteChip(urlConfig: urlConfig) {
                            websiteConfigs.removeAll { $0.id == urlConfig.id }
                        }
                    }
                }
            }

            if !triggerWords.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(triggerWords, id: \.self) { word in
                        TriggerWordChip(word: word) {
                            triggerWords.removeAll { $0 == word }
                        }
                    }
                }
            }
        }
    }

    private func reservedAppBundleIds(excluding groupId: UUID) -> Set<String> {
        let groupedApps =
            triggerGroups
            .filter { $0.id != groupId }
            .flatMap { $0.appConfigs.map(\.bundleIdentifier) }
        return Set(appConfigs.map(\.bundleIdentifier) + groupedApps)
    }

    private func reservedWebsites(excluding groupId: UUID) -> Set<String> {
        let groupedWebsites =
            triggerGroups
            .filter { $0.id != groupId }
            .flatMap { $0.urlConfigs.map { cleanURL($0.url) } }
        return Set(websiteConfigs.map { cleanURL($0.url) } + groupedWebsites)
    }
}
