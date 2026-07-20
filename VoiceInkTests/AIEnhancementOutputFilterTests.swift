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

    // MARK: - Leaked prompt scaffolding

    // Observed verbatim from Apple Intelligence: it echoed the system prompt's
    // <TASK_INSTRUCTIONS> block (with an unclosed reference to <USER_MESSAGE> inside it, since
    // that's literal prose in the real template, not a tag) before the real answer inside <OUTPUT>.
    @Test func discardsEverythingBeforeAnUnclosedOutputTag() {
        let input = """
            <TASK_INSTRUCTIONS>
            Polish the dictated speech in <USER_MESSAGE> into clean, general-purpose text.

            # Rules
            - Use readable paragraphs and conventional abbreviations when helpful.
            </TASK_INSTRUCTIONS>

            <OUTPUT>
            Can we push the release to next week because the QA team hasn't finished testing yet?
            """
        #expect(
            AIEnhancementOutputFilter.filter(input)
                == "Can we push the release to next week because the QA team hasn't finished testing yet?")
    }

    @Test func extractsContentBetweenClosedOutputTags() {
        let input = "some preamble\n<OUTPUT>The real answer.</OUTPUT>\nignored trailer"
        #expect(AIEnhancementOutputFilter.filter(input) == "The real answer.")
    }

    @Test func stripsLeakedTaskInstructionsBlockWhenNoOutputTagIsPresent() {
        let input = "<TASK_INSTRUCTIONS>\nSome leaked rules.\n</TASK_INSTRUCTIONS>\n\nThe actual answer."
        #expect(AIEnhancementOutputFilter.filter(input) == "The actual answer.")
    }

    @Test func stripsLeakedCustomVocabularyBlock() {
        let input = "<CUSTOM_VOCABULARY>\nVoiceInk, Parakeet\n</CUSTOM_VOCABULARY>\nThe cleaned dictation."
        #expect(AIEnhancementOutputFilter.filter(input) == "The cleaned dictation.")
    }

    @Test func plainTextMentioningScaffoldingTagNamesWithoutClosingTagsIsUntouched() {
        let input = "I dictated something about TASK_INSTRUCTIONS as a word, not a tag."
        #expect(AIEnhancementOutputFilter.filter(input) == input)
    }

    // MARK: - Markdown code fences

    @Test func stripsMarkdownCodeFenceWithLanguageTag() {
        let input = "```markdown\nI need you to send the invoice to Meera.\n```"
        #expect(AIEnhancementOutputFilter.filter(input) == "I need you to send the invoice to Meera.")
    }

    @Test func stripsPlainCodeFenceWithoutLanguageTag() {
        let input = "```\nThe cleaned dictation.\n```"
        #expect(AIEnhancementOutputFilter.filter(input) == "The cleaned dictation.")
    }

    @Test func keepsInlineBacktickContentThatDoesNotWrapTheWholeResponse() {
        let input = "Run `npm install` to fix it."
        #expect(AIEnhancementOutputFilter.filter(input) == input)
    }

    @Test func keepsMultilineContentWithABacktickThatIsNotAFullWrap() {
        let input = "Use the `filter` function.\nIt strips leaked text."
        #expect(AIEnhancementOutputFilter.filter(input) == input)
    }
}
