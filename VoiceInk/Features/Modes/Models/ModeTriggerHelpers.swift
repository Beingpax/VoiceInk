import Foundation

struct TriggerSnapshot {
    let appBundleIds: Set<String>
    let websites: Set<String>
    let templateIds: Set<String>

    init(
        appConfigs: [AppConfig], websiteConfigs: [URLConfig], triggerGroups: [ModeTriggerGroup],
        cleanURL: (String) -> String
    ) {
        appBundleIds = Set(
            appConfigs.map(\.bundleIdentifier) + triggerGroups.flatMap { $0.appConfigs.map(\.bundleIdentifier) })
        websites = Set(
            websiteConfigs.map { cleanURL($0.url) } + triggerGroups.flatMap { $0.urlConfigs.map { cleanURL($0.url) } })
        templateIds = Set(triggerGroups.compactMap(\.templateId))
    }
}

extension ModeTriggerGroup {
    var summaryText: String {
        let appCount = appConfigs.count
        let websiteCount = urlConfigs.count

        switch (appCount, websiteCount) {
        case (0, 0):
            return String(localized: "No triggers")
        case (0, _):
            return countText(websiteCount, key: "%lld websites")
        case (_, 0):
            return countText(appCount, key: "%lld apps")
        default:
            return "\(countText(appCount, key: "%lld apps")) · \(countText(websiteCount, key: "%lld websites"))"
        }
    }

    private func countText(_ count: Int, key: String) -> String {
        if key == "%lld apps" {
            return String(localized: "\(count) apps")
        }
        return String(localized: "\(count) websites")
    }
}
