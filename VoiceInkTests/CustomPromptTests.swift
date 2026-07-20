import Testing

@testable import VoiceInk

// No prior coverage existed for CustomPrompt (untested tier). Adding tests for the
// provider-aware prompt selection introduced to fix Apple Intelligence's low-quality
// enhancement output (see AIPrompts.appleIntelligenceEnhancementSystemTemplate).
struct CustomPromptTests {

    private func prompt(useSystemInstructions: Bool = true) -> CustomPrompt {
        CustomPrompt(title: "Default", promptText: "Polish the text.", useSystemInstructions: useSystemInstructions)
    }

    @Test func nonAppleIntelligenceProvidersUseTheFullTemplate() {
        let text = prompt().finalPromptText(for: .openAI)

        #expect(text.contains("# System Instructions"))
        #expect(text.contains("<TASK_INSTRUCTIONS>"))
        #expect(text.contains("Polish the text."))
    }

    @Test func nilProviderFallsBackToTheFullTemplate() {
        let text = prompt().finalPromptText(for: nil)

        #expect(text.contains("# System Instructions"))
    }

    @Test func appleIntelligenceUsesTheCompactTemplate() {
        let text = prompt().finalPromptText(for: .appleIntelligence)

        #expect(!text.contains("# System Instructions"))
        #expect(!text.contains("<TASK_INSTRUCTIONS>"))
        #expect(text.contains("Polish the text."))
    }

    @Test func appleIntelligenceTemplateIncludesRepairExamples() {
        let text = prompt().finalPromptText(for: .appleIntelligence)

        #expect(text.contains("Can you is there a way that you can improve their output?"))
        #expect(text.contains("Is there a way to improve their output?"))
    }

    @Test func promptsWithoutSystemInstructionsAreReturnedAsIsRegardlessOfProvider() {
        let rewritePrompt = CustomPrompt(
            title: "Rewrite", promptText: "Rewrite per instructions.", useSystemInstructions: false)

        #expect(rewritePrompt.finalPromptText(for: .appleIntelligence) == "Rewrite per instructions.")
        #expect(rewritePrompt.finalPromptText(for: .openAI) == "Rewrite per instructions.")
        #expect(rewritePrompt.finalPromptText(for: nil) == "Rewrite per instructions.")
    }

    @Test func legacyFinalPromptTextPropertyMatchesNilProviderBehavior() {
        let withProperty = prompt().finalPromptText
        let withNilProvider = prompt().finalPromptText(for: nil)

        #expect(withProperty == withNilProvider)
    }
}
