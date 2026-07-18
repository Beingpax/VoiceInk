import Foundation
import Testing

@testable import VoiceInk

// Personal Dictionary is core to why this fork exists (accent/vocabulary
// tuning — see CONTEXT.md). These models carry almost no logic today, but
// pinning down their default behavior now protects against a silent
// regression (e.g. a default flipping from enabled to disabled) later,
// once Phase 1 wires real usage through them.
struct VocabularyWordTests {

    @Test func storesTheWordAsProvided() {
        let word = VocabularyWord(word: "Bengaluru")
        #expect(word.word == "Bengaluru")
    }

    @Test func defaultsDateAddedToNow() {
        let before = Date()
        let word = VocabularyWord(word: "Bengaluru")
        let after = Date()
        #expect(word.dateAdded >= before && word.dateAdded <= after)
    }
}

struct WordReplacementTests {

    @Test func storesOriginalAndReplacementText() {
        let replacement = WordReplacement(originalText: "there", replacementText: "their")
        #expect(replacement.originalText == "there")
        #expect(replacement.replacementText == "their")
    }

    @Test func isEnabledByDefault() {
        let replacement = WordReplacement(originalText: "a", replacementText: "b")
        #expect(replacement.isEnabled == true)
    }

    @Test func canBeCreatedDisabled() {
        let replacement = WordReplacement(originalText: "a", replacementText: "b", isEnabled: false)
        #expect(replacement.isEnabled == false)
    }
}
