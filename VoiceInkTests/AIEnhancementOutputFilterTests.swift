import Testing

@testable import VoiceInk

struct AIEnhancementOutputFilterTests {

    @Test func stripsThinkingTags() {
        let input = "<thinking>let me consider this</thinking>Hello there."
        #expect(AIEnhancementOutputFilter.filter(input) == "Hello there.")
    }

    @Test func stripsThinkTags() {
        let input = "<think>internal monologue</think>Final answer."
        #expect(AIEnhancementOutputFilter.filter(input) == "Final answer.")
    }

    @Test func stripsReasoningTags() {
        let input = "<reasoning>step by step</reasoning>Done."
        #expect(AIEnhancementOutputFilter.filter(input) == "Done.")
    }

    @Test func stripsMultilineTagContent() {
        let input = "<thinking>\nline one\nline two\n</thinking>Result."
        #expect(AIEnhancementOutputFilter.filter(input) == "Result.")
    }

    @Test func leavesPlainTextUntouched() {
        let input = "Nothing to strip here."
        #expect(AIEnhancementOutputFilter.filter(input) == input)
    }

    @Test func trimsWhitespaceLeftBehindByStrippedTags() {
        let input = "  <thinking>x</thinking>   Trimmed result.   "
        #expect(AIEnhancementOutputFilter.filter(input) == "Trimmed result.")
    }
}
