import Testing

@testable import VoiceInk

struct WordLevelDiffTests {

    @Test func identicalTextsAreAllEqual() {
        let ops = WordLevelDiff.compute(original: "the quick brown fox", enhanced: "the quick brown fox")

        #expect(ops == [.equal("the"), .equal("quick"), .equal("brown"), .equal("fox")])
    }

    @Test func casingFixIsASubstitutionNotAnEqual() {
        // Deliberately different from WordErrorRateCalculator: a casing fix IS a visible change
        // here, since the whole point is showing a human what Apple Intelligence touched.
        let ops = WordLevelDiff.compute(original: "the meeting is at 3 pm", enhanced: "The meeting is at 3 PM")

        #expect(ops == [
            .substitution(from: "the", to: "The"),
            .equal("meeting"), .equal("is"), .equal("at"), .equal("3"),
            .substitution(from: "pm", to: "PM"),
        ])
    }

    @Test func punctuationFixIsASubstitution() {
        let ops = WordLevelDiff.compute(original: "call john at 5", enhanced: "Call John at 5.")

        #expect(ops == [
            .substitution(from: "call", to: "Call"),
            .substitution(from: "john", to: "John"),
            .equal("at"),
            .substitution(from: "5", to: "5."),
        ])
    }

    @Test func wordInsertedByEnhancement() {
        let ops = WordLevelDiff.compute(original: "meeting at 3", enhanced: "The meeting is at 3")

        #expect(ops == [.insertion("The"), .equal("meeting"), .insertion("is"), .equal("at"), .equal("3")])
    }

    @Test func wordDeletedByEnhancement() {
        let ops = WordLevelDiff.compute(original: "um so the meeting is at 3", enhanced: "the meeting is at 3")

        #expect(ops == [
            .deletion("um"), .deletion("so"), .equal("the"), .equal("meeting"), .equal("is"), .equal("at"),
            .equal("3"),
        ])
    }

    @Test func emptyOriginalIsAllInsertions() {
        let ops = WordLevelDiff.compute(original: "", enhanced: "hello world")

        #expect(ops == [.insertion("hello"), .insertion("world")])
    }

    @Test func emptyEnhancedIsAllDeletions() {
        let ops = WordLevelDiff.compute(original: "hello world", enhanced: "")

        #expect(ops == [.deletion("hello"), .deletion("world")])
    }

    @Test func bothEmptyIsNoOperations() {
        #expect(WordLevelDiff.compute(original: "", enhanced: "") == [])
    }

    @Test func tokenizeSplitsOnWhitespaceAndPreservesPunctuation() {
        #expect(WordLevelDiff.tokenize("Hello, world!") == ["Hello,", "world!"])
        #expect(WordLevelDiff.tokenize("  extra   spaces  ") == ["extra", "spaces"])
    }
}
