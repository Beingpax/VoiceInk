//
//  TranscriptionOutputFilterTests.swift
//  VoiceInkTests
//

import XCTest
@testable import VoiceInk

final class TranscriptionOutputFilterTests: XCTestCase {
    func testGermanUmSurvivesDefaultFillers() {
        let sentence = "Wir diktieren, um weniger schreiben zu müssen."
        XCTAssertEqual(
            TranscriptionOutputFilter.filter(sentence, language: "de", fillers: FillerWordManager.defaultFillerWords),
            sentence
        )
    }

    func testGermanLocalesKeepUm() {
        let fillers = FillerWordManager.defaultFillerWords
        XCTAssertEqual(
            TranscriptionOutputFilter.filter("Um 8 Uhr beginnt es.", language: "de-DE", fillers: fillers),
            "Um 8 Uhr beginnt es."
        )
        XCTAssertEqual(
            TranscriptionOutputFilter.filter("um die Ecke", language: "de-DE", fillers: fillers),
            "um die Ecke"
        )
        let sentence = "Wir diktieren, um weniger schreiben zu müssen."
        XCTAssertEqual(
            TranscriptionOutputFilter.filter(sentence, language: "de-AT", fillers: fillers),
            sentence
        )
        XCTAssertEqual(
            TranscriptionOutputFilter.filter(sentence, language: "de-CH", fillers: fillers),
            sentence
        )
    }

    func testEnglishStillStripsFillers() {
        let fillers = FillerWordManager.defaultFillerWords
        for language in ["en", "en-GB"] {
            XCTAssertEqual(
                TranscriptionOutputFilter.filter("I was, um, thinking.", language: language, fillers: fillers),
                "I was, thinking."
            )
            XCTAssertEqual(
                TranscriptionOutputFilter.filter("Um, I think so.", language: language, fillers: fillers),
                "I think so."
            )
            XCTAssertEqual(
                TranscriptionOutputFilter.filter("I was um thinking.", language: language, fillers: fillers),
                "I was thinking."
            )
        }
    }

    func testAutomaticAndMissingLanguageStillStripUm() {
        let input = "Wir diktieren, um weniger schreiben zu müssen."
        let expected = "Wir diktieren, weniger schreiben zu müssen."
        let fillers = FillerWordManager.defaultFillerWords
        XCTAssertEqual(
            TranscriptionOutputFilter.filter(input, language: "auto", fillers: fillers),
            expected
        )
        XCTAssertEqual(
            TranscriptionOutputFilter.filter(input, language: nil, fillers: fillers),
            expected
        )
        XCTAssertEqual(
            TranscriptionOutputFilter.filter(input, language: "", fillers: fillers),
            expected
        )
    }

    func testCustomFillersStayGlobal() {
        XCTAssertEqual(
            TranscriptionOutputFilter.filter(
                "Wir diktieren, please, um weniger schreiben zu müssen.",
                language: "de",
                fillers: FillerWordManager.defaultFillerWords + ["please"]
            ),
            "Wir diktieren, um weniger schreiben zu müssen."
        )
    }

    func testGermanStillStripsOtherDefaultFillers() {
        XCTAssertEqual(
            TranscriptionOutputFilter.filter(
                "Wir diktieren, uh, um weniger hmm schreiben zu müssen.",
                language: "de-DE",
                fillers: FillerWordManager.defaultFillerWords
            ),
            "Wir diktieren, um weniger schreiben zu müssen."
        )
    }

    func testPortugueseKeepsUm() {
        let sentence = "Eu tenho um carro."
        XCTAssertEqual(
            TranscriptionOutputFilter.filter(sentence, language: "pt-BR", fillers: FillerWordManager.defaultFillerWords),
            sentence
        )
    }

    func testOtherLanguagesKeepDefaultFillers() {
        let fillers = FillerWordManager.defaultFillerWords
        XCTAssertEqual(
            TranscriptionOutputFilter.filter("Pues, uh, no sé.", language: "es-US", fillers: fillers),
            "Pues, no sé."
        )
        XCTAssertEqual(
            TranscriptionOutputFilter.filter("Je pense, um, que oui.", language: "fr", fillers: fillers),
            "Je pense, que oui."
        )
    }

    func testWholeWordAndQuotedUm() {
        let fillers = FillerWordManager.defaultFillerWords
        XCTAssertEqual(
            TranscriptionOutputFilter.filter("Der Umfang ist, um, groß.", language: "en", fillers: fillers),
            "Der Umfang ist, groß."
        )
        XCTAssertEqual(
            TranscriptionOutputFilter.filter("Wir gehen zum Markt, um, jetzt.", language: "en", fillers: fillers),
            "Wir gehen zum Markt, jetzt."
        )
        let quoted = "The word is \"um\"."
        XCTAssertEqual(
            TranscriptionOutputFilter.filter(quoted, language: "en", fillers: fillers),
            quoted
        )
    }
}
