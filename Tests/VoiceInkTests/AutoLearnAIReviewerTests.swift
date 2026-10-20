import Testing
@testable import VoiceInk

struct AutoLearnAIReviewerTests {
    @Test func jsonPayloadUnwrapsMarkdownCodeFences() {
        let array = #"[{"candidateID":0,"learningAction":"rejectCorrection","incorrectTextToReplace":null,"correctedVocabularyTerm":null}]"#
        let responses = [
            array,
            "  \(array)\n",
            "```json\n\(array)\n```",
            "```JSON\n\(array)\n```\n",
            "```\n\(array)\n```",
            "```json \(array) ```",
            "```json \(array)\n```",
            "``` \(array)\n```",
            "``` json \(array) ```",
            "``` \tJSON \(array) ```",
        ]

        for response in responses {
            #expect(AutoLearnAIReviewer.jsonPayload(fromModelResponse: response) == array, "response: \(response)")
        }
    }

    @Test func jsonPayloadPreservesMultilineJSONBeginningOnFenceLine() {
        let array = """
            [
            {"candidateID":0,"learningAction":"rejectCorrection","incorrectTextToReplace":null,"correctedVocabularyTerm":null}
            ]
            """
        let responses = [
            "```json \(array)\n```",
            "``` json \(array)\n```",
            "``` \(array)\n```",
        ]

        for response in responses {
            #expect(AutoLearnAIReviewer.jsonPayload(fromModelResponse: response) == array, "response: \(response)")
        }
    }
}
