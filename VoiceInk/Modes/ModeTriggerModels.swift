import Foundation

struct ModeTriggerGroup: Codable, Identifiable, Equatable {
    let id: UUID
    var templateId: String?
    var name: String
    var appConfigs: [AppConfig]
    var urlConfigs: [URLConfig]

    init(
        id: UUID = UUID(),
        templateId: String? = nil,
        name: String,
        appConfigs: [AppConfig] = [],
        urlConfigs: [URLConfig] = []
    ) {
        self.id = id
        self.templateId = templateId
        self.name = name
        self.appConfigs = appConfigs
        self.urlConfigs = urlConfigs
    }

    var isEmpty: Bool {
        appConfigs.isEmpty && urlConfigs.isEmpty
    }
}

extension ModeConfig {
    var allAppConfigs: [AppConfig] {
        (appConfigs ?? []) + (triggerGroups ?? []).flatMap(\.appConfigs)
    }

    var allURLConfigs: [URLConfig] {
        (urlConfigs ?? []) + (triggerGroups ?? []).flatMap(\.urlConfigs)
    }
}

extension Array where Element == ModeTriggerGroup {
    func containsTemplate(_ templateId: String) -> Bool {
        contains { $0.templateId == templateId }
    }
}
