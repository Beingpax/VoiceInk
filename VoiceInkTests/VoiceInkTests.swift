//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Testing
@testable import VoiceInk

struct VoiceInkTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

struct TranscriptionOutputFilterTrailingPeriodTests {
    @Test func removesSingleTrailingPeriod() {
        #expect(TranscriptionOutputFilter.removeTrailingPeriod(from: "Sounds good.") == "Sounds good")
    }

    @Test func leavesMidSentencePunctuationAlone() {
        #expect(
            TranscriptionOutputFilter.removeTrailingPeriod(from: "Hello, world. How are you.")
            == "Hello, world. How are you"
        )
    }

    @Test func leavesOtherTerminatorsAlone() {
        #expect(TranscriptionOutputFilter.removeTrailingPeriod(from: "Really?") == "Really?")
        #expect(TranscriptionOutputFilter.removeTrailingPeriod(from: "Wow!") == "Wow!")
    }

    @Test func preservesTrailingWhitespace() {
        #expect(TranscriptionOutputFilter.removeTrailingPeriod(from: "Sounds good. ") == "Sounds good ")
        #expect(TranscriptionOutputFilter.removeTrailingPeriod(from: "Sounds good.\n") == "Sounds good\n")
    }

    @Test func onlyStripsOnePeriod() {
        // Ellipses and other repeated punctuation should not be eaten.
        #expect(TranscriptionOutputFilter.removeTrailingPeriod(from: "Wait...") == "Wait..")
    }

    @Test func leavesTextWithoutTrailingPeriodUnchanged() {
        #expect(TranscriptionOutputFilter.removeTrailingPeriod(from: "Hello world") == "Hello world")
        #expect(TranscriptionOutputFilter.removeTrailingPeriod(from: "") == "")
        #expect(TranscriptionOutputFilter.removeTrailingPeriod(from: "   ") == "   ")
    }
}
