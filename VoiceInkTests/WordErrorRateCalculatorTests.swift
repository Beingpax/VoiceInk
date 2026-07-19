import Testing

@testable import VoiceInk

struct WordErrorRateCalculatorTests {

    @Test func identicalTranscriptsHaveZeroErrors() {
        let result = WordErrorRateCalculator.evaluate(
            reference: "the quick brown fox", hypothesis: "the quick brown fox")

        #expect(result.substitutions == 0)
        #expect(result.deletions == 0)
        #expect(result.insertions == 0)
        #expect(result.wordErrorRate == 0)
    }

    @Test func singleSubstitution() {
        // "quick" -> "slow": one substitution out of 4 reference words.
        let result = WordErrorRateCalculator.evaluate(
            reference: "the quick brown fox", hypothesis: "the slow brown fox")

        #expect(result.substitutions == 1)
        #expect(result.deletions == 0)
        #expect(result.insertions == 0)
        #expect(result.wordErrorRate == 0.25)
    }

    @Test func singleDeletion() {
        // "brown" missing from hypothesis: one deletion out of 4 reference words.
        let result = WordErrorRateCalculator.evaluate(reference: "the quick brown fox", hypothesis: "the quick fox")

        #expect(result.substitutions == 0)
        #expect(result.deletions == 1)
        #expect(result.insertions == 0)
        #expect(result.wordErrorRate == 0.25)
    }

    @Test func singleInsertion() {
        // "very" inserted, not in reference: one insertion out of 4 reference words.
        let result = WordErrorRateCalculator.evaluate(
            reference: "the quick brown fox", hypothesis: "the very quick brown fox")

        #expect(result.substitutions == 0)
        #expect(result.deletions == 0)
        #expect(result.insertions == 1)
        #expect(result.wordErrorRate == 0.25)
    }

    @Test func mixOfAllThreeErrorTypes() {
        // Reference: "i went to the market yesterday" (6 words)
        // Hypothesis: "i went the supermarket today"
        //   "to" deleted, "market"->"supermarket" substituted, "yesterday"->"today" substituted
        let result = WordErrorRateCalculator.evaluate(
            reference: "i went to the market yesterday", hypothesis: "i went the supermarket today")

        #expect(result.deletions == 1)
        #expect(result.substitutions == 2)
        #expect(result.insertions == 0)
        #expect(result.referenceWordCount == 6)
        #expect(result.errorCount == 3)
    }

    @Test func comparisonIsCaseInsensitive() {
        let result = WordErrorRateCalculator.evaluate(reference: "Hello World", hypothesis: "hello world")

        #expect(result.errorCount == 0)
    }

    @Test func comparisonIgnoresPunctuation() {
        let result = WordErrorRateCalculator.evaluate(reference: "Hello, world!", hypothesis: "Hello world")

        #expect(result.errorCount == 0)
    }

    @Test func emptyHypothesisAgainstNonEmptyReferenceIsAllDeletions() {
        let result = WordErrorRateCalculator.evaluate(reference: "one two three", hypothesis: "")

        #expect(result.deletions == 3)
        #expect(result.insertions == 0)
        #expect(result.substitutions == 0)
        #expect(result.wordErrorRate == 1.0)
    }

    @Test func nonEmptyHypothesisAgainstEmptyReferenceIsWorstCaseNotPerfect() {
        // Regression test: an earlier version of this calculator returned 0.0 (perfect) here
        // because it special-cased referenceWordCount == 0 without checking errorCount first.
        let result = WordErrorRateCalculator.evaluate(reference: "", hypothesis: "hallucinated words")

        #expect(result.insertions == 2)
        #expect(result.referenceWordCount == 0)
        #expect(result.wordErrorRate == 1.0)
    }

    @Test func bothEmptyIsAPerfectMatch() {
        let result = WordErrorRateCalculator.evaluate(reference: "", hypothesis: "")

        #expect(result.errorCount == 0)
        #expect(result.wordErrorRate == 0)
    }

    @Test func normalizeStripsPunctuationAndLowercases() {
        #expect(WordErrorRateCalculator.normalize("Hello, World!") == ["hello", "world"])
        #expect(WordErrorRateCalculator.normalize("  extra   spaces  ") == ["extra", "spaces"])
    }
}
