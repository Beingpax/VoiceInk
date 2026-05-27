import Foundation

struct TriggerSnapshot {
    let appBundleIds: Set<String>
    let websites: Set<String>
    let templateIds: Set<String>

    init(appConfigs: [AppConfig], websiteConfigs: [URLConfig], triggerGroups: [ModeTriggerGroup], cleanURL: (String) -> String) {
        appBundleIds = Set(appConfigs.map(\.bundleIdentifier) + triggerGroups.flatMap { $0.appConfigs.map(\.bundleIdentifier) })
        websites = Set(websiteConfigs.map { cleanURL($0.url) } + triggerGroups.flatMap { $0.urlConfigs.map { cleanURL($0.url) } })
        templateIds = Set(triggerGroups.compactMap(\.templateId))
    }
}

extension ModeTriggerGroup {
    var summaryText: String {
        let appCount = appConfigs.count
        let websiteCount = urlConfigs.count

        switch (appCount, websiteCount) {
        case (0, 0):
            return "No triggers"
        case (0, _):
            return countText(websiteCount, singular: "website", plural: "websites")
        case (_, 0):
            return countText(appCount, singular: "app", plural: "apps")
        default:
            return "\(countText(appCount, singular: "app", plural: "apps")) · \(countText(websiteCount, singular: "website", plural: "websites"))"
        }
    }

    private func countText(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }
}
