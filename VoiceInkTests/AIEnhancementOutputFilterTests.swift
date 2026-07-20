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

    // Observed verbatim from Apple Intelligence (Foundation Models) despite the system prompt
    // saying "Return only the final text": a chatty lead-in plus quotes around the real output.
    @Test func stripsAppleIntelligenceStylePreambleAndWrappingQuotes() {
        let input = """
            Sure, here is the polished version of your text:

            "I was thinking that we should meet tomorrow at around 10 AM."
            """
        #expect(
            AIEnhancementOutputFilter.filter(input)
                == "I was thinking that we should meet tomorrow at around 10 AM.")
    }

    @Test func stripsPreambleWithoutQuotes() {
        let input = "Here's the revised text:\nMeet me at noon."
        #expect(AIEnhancementOutputFilter.filter(input) == "Meet me at noon.")
    }

    @Test func stripsCurlyWrappingQuotesAfterPreamble() {
        let input = "Certainly! Here is the cleaned-up version:\n\n\u{201C}Send the report by 6 PM.\u{201D}"
        #expect(AIEnhancementOutputFilter.filter(input) == "Send the report by 6 PM.")
    }

    @Test func keepsQuotesWhenThereIsNoPreamble() {
        let input = "\"Quoted text the user actually dictated.\""
        #expect(AIEnhancementOutputFilter.filter(input) == input)
    }

    @Test func keepsFirstLineEndingInColonWhenItIsNotAChattyLead() {
        let input = "Agenda for tomorrow:\n- Review eval set\n- Fix crash"
        #expect(AIEnhancementOutputFilter.filter(input) == input)
    }

    @Test func keepsDictatedContentThatStartsWithHereButIsNotModelChatter() {
        let input = "Here are the three options:\n- Option A\n- Option B\n- Option C"
        #expect(AIEnhancementOutputFilter.filter(input) == input)
    }

    @Test func keepsPreambleLookalikeWhenNothingFollowsIt() {
        let input = "Sure, here is the thing you asked about:"
        #expect(AIEnhancementOutputFilter.filter(input) == input)
    }

    @Test func keepsQuotesWhenInteriorAlsoContainsQuotes() {
        let input = "Sure, here is the text:\n\n\"She said \"hello\" to everyone.\""
        #expect(AIEnhancementOutputFilter.filter(input) == "\"She said \"hello\" to everyone.\"")
    }
}
