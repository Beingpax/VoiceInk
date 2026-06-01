import Foundation

enum StarterModePromptSeeder {
    static func hasPrompts(
        for kinds: [StarterModeKind],
        in prompts: [CustomPrompt]
    ) -> Bool {
        requiredPromptIds(for: kinds).allSatisfy { promptId in
            prompts.contains { $0.id == promptId }
        }
    }

    static func ensurePrompts(
        for kinds: [StarterModeKind],
        in prompts: [CustomPrompt]
    ) -> (prompts: [CustomPrompt], didChange: Bool) {
        let requiredPromptIds = requiredPromptIds(for: kinds)
        guard !requiredPromptIds.isEmpty else {
            return (prompts, false)
        }

        var updatedPrompts = prompts
        var didChange = false

        for promptId in requiredPromptIds where !updatedPrompts.contains(where: { $0.id == promptId }) {
            guard let seedPrompt = PromptTemplates.seedPrompts.first(where: { $0.id == promptId }) else {
                continue
            }

            updatedPrompts.append(seedPrompt)
            didChange = true
        }

        return (updatedPrompts, didChange)
    }

    private static func requiredPromptIds(for kinds: [StarterModeKind]) -> [UUID] {
        var seenPromptIds = Set<UUID>()

        return kinds.compactMap { kind in
            guard let promptId = StarterModeCatalog.templates.first(where: { $0.kind == kind })?.promptId,
                  !seenPromptIds.contains(promptId) else {
                return nil
            }

            seenPromptIds.insert(promptId)
            return promptId
        }
    }
}
