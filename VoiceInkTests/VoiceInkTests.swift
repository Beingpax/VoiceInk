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

struct ChunkSplittingTests {

    @Test func shortTextIsReturnedAsSingleChunk() {
        let text = "hello world"
        #expect(CursorPaster.splitIntoChunks(text, maxLength: 250) == [text])
    }

    @Test func textEqualToMaxLengthIsNotSplit() {
        let text = String(repeating: "a", count: 100)
        #expect(CursorPaster.splitIntoChunks(text, maxLength: 100) == [text])
    }

    @Test func reassemblyReproducesOriginalExactly() {
        let text = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 50)
        let chunks = CursorPaster.splitIntoChunks(text, maxLength: 100)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == text)
    }

    @Test func chunksStayWithinMaxLengthWhenWhitespaceIsAvailable() {
        let text = String(repeating: "word ", count: 200)
        let maxLength = 80
        let chunks = CursorPaster.splitIntoChunks(text, maxLength: maxLength)
        for chunk in chunks {
            #expect(chunk.count <= maxLength)
        }
        #expect(chunks.joined() == text)
    }

    @Test func splitsOnWhitespaceRatherThanMidWord() {
        let text = "aaaa bbbb cccc dddd eeee"
        let chunks = CursorPaster.splitIntoChunks(text, maxLength: 10)
        #expect(chunks.joined() == text)
        // Every chunk but the last should end on the whitespace it broke at,
        // so no four-letter word is torn across a boundary.
        for chunk in chunks.dropLast() {
            #expect(chunk.hasSuffix(" "))
        }
    }

    @Test func oversizedRunWithoutWhitespaceHardSplits() {
        let text = String(repeating: "x", count: 1000)
        let maxLength = 250
        let chunks = CursorPaster.splitIntoChunks(text, maxLength: maxLength)
        #expect(chunks.count == 4)
        for chunk in chunks {
            #expect(chunk.count <= maxLength)
        }
        #expect(chunks.joined() == text)
    }

    @Test func multilineTextReassembles() {
        let text = "line one\nline two\n\nparagraph two is a little longer than the rest of them"
        let chunks = CursorPaster.splitIntoChunks(text, maxLength: 16)
        #expect(chunks.joined() == text)
    }

    @Test func nonPositiveMaxLengthReturnsWholeText() {
        let text = "anything"
        #expect(CursorPaster.splitIntoChunks(text, maxLength: 0) == [text])
        #expect(CursorPaster.splitIntoChunks(text, maxLength: -10) == [text])
    }

    @Test func graphemeClustersAreNotCorrupted() {
        // Emoji with a skin-tone modifier is a single multi-scalar grapheme;
        // index-based splitting must keep each cluster intact.
        let text = String(repeating: "👍🏽 ", count: 100)
        let chunks = CursorPaster.splitIntoChunks(text, maxLength: 20)
        #expect(chunks.joined() == text)
    }
}
