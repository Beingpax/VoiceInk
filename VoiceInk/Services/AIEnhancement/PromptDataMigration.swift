import Foundation

enum PromptDataMigration {
    private static let seedVersionKey = "PromptDataMigration.seededTemplatePromptsVersion"
    private static let currentSeedVersion = 2

    static func migrate(_ prompts: [CustomPrompt], defaults: UserDefaults = .standard) -> (prompts: [CustomPrompt], didChange: Bool) {
        var migratedPrompts = prompts
        var didChange = false
        let seedVersion = defaults.integer(forKey: seedVersionKey)

        if seedVersion < currentSeedVersion {
            let seedResult = ensureDefaultPromptsExist(in: migratedPrompts)
            migratedPrompts = seedResult.prompts
            didChange = seedResult.didChange
            defaults.set(currentSeedVersion, forKey: seedVersionKey)
        }

        return (migratedPrompts, didChange)
    }

    static func ensureDefaultPromptsExist(in prompts: [CustomPrompt]) -> (prompts: [CustomPrompt], didChange: Bool) {
        var migratedPrompts = prompts
        var didChange = false

        for seedPrompt in PromptTemplates.seedPrompts where shouldInsert(seedPrompt, into: migratedPrompts) {
            migratedPrompts.append(seedPrompt)
            didChange = true
        }

        return (migratedPrompts, didChange)
    }

    private static func shouldInsert(_ seedPrompt: CustomPrompt, into prompts: [CustomPrompt]) -> Bool {
        if prompts.contains(where: { $0.id == seedPrompt.id }) {
            return false
        }

        let requiresStableID = seedPrompt.id == PromptTemplates.defaultPromptId

        if requiresStableID {
            return true
        }

        let seedTitle = normalizedTitle(seedPrompt.title)
        return !prompts.contains { normalizedTitle($0.title) == seedTitle }
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
