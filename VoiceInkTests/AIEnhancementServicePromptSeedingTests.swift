import Foundation
import Testing

@testable import VoiceInk

// Regression tests for the "Apple Intelligence does nothing" bug: on a store that never saved
// prompts, the app had zero prompts, so every mode's AI enhancement was permanently
// "not configured" and silently skipped (confirmed via 128/128 enhancement_skipped telemetry).
struct AIEnhancementServicePromptSeedingTests {

    @Test func neverSavedStoreSeedsTheBuiltInTemplates() {
        let prompts = AIEnhancementService.initialPrompts(fromSaved: nil)

        #expect(!prompts.isEmpty)
        #expect(prompts.map(\.id) == PromptTemplates.seedPrompts.map(\.id))
    }

    @Test func seededPromptsIncludeTheDefaultTemplateWithItsStableId() {
        let prompts = AIEnhancementService.initialPrompts(fromSaved: nil)

        #expect(prompts.contains { $0.id == PromptTemplates.defaultPromptId && $0.title == "Default" })
    }

    @Test func savedPromptsAreDecodedNotReplaced() throws {
        let saved = [CustomPrompt(title: "Mine", promptText: "Do my thing")]
        let data = try JSONEncoder().encode(saved)

        let prompts = AIEnhancementService.initialPrompts(fromSaved: data)

        #expect(prompts.count == 1)
        #expect(prompts[0].title == "Mine")
    }

    @Test func deliberatelyEmptySavedStoreStaysEmpty() throws {
        let data = try JSONEncoder().encode([CustomPrompt]())

        let prompts = AIEnhancementService.initialPrompts(fromSaved: data)

        #expect(prompts.isEmpty)
    }

    @Test func corruptedSavedStoreFallsBackToSeeds() {
        let prompts = AIEnhancementService.initialPrompts(fromSaved: Data("not json".utf8))

        #expect(prompts.map(\.id) == PromptTemplates.seedPrompts.map(\.id))
    }
}
