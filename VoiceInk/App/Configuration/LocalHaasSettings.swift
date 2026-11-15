import Foundation

/// Built-in offline route; executable code is bundled, model data is downloaded on first use.
enum LocalHaasSettings {
    static let modelID = UUID(uuidString: "53C63B57-9BC8-4CD8-A536-4D7358C8A003")!
    static let endpoint = "voiceink-local://haas"
    static let modelName = "Haas-ja-v1.0"
    static var selectionKey: String { "Custom:\(modelID.uuidString)" }

    static var model: CustomCloudModel {
        CustomCloudModel(
            id: modelID, name: "haas-ja-v1.0", displayName: "HaaS-ja + Horizon",
            description: "ローカルのHaaS-jaで文字起こしし、Horizonで句読点を補完します。初回にモデルをダウンロードします。",
            apiEndpoint: endpoint, modelName: modelName, isMultilingual: true,
            supportedLanguages: ["auto": "Auto-detect", "ja": "Japanese"]
        )
    }

    static func registerDefaults(defaults: UserDefaults = .standard) {
        // Registration supplies defaults without overwriting a user's saved model list or selection.
        guard let data = try? JSONEncoder().encode([model]) else { return }
        defaults.register(defaults: [
            "customCloudModels": data,
            "CurrentTranscriptionModel": selectionKey,
        ])
    }
}
