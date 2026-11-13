import Testing
@testable import VoiceInk

struct ZoomScribeProviderTests {
    // The test target does not link LLMkit, so these tests use the status-code overload.
    // shouldTranscode(after:) is not exercised for LLMKitError values here.

    @Test func containerAndSizeRejectionsTranscode() {
        #expect(ZoomScribeProvider.shouldTranscode(statusCode: 413))
        #expect(ZoomScribeProvider.shouldTranscode(statusCode: 415))
    }

    @Test func otherStatusCodesDoNotTranscode() {
        #expect(!ZoomScribeProvider.shouldTranscode(statusCode: 401))
        #expect(!ZoomScribeProvider.shouldTranscode(statusCode: 500))
    }

    @Test func nonLLMKitErrorDoesNotTranscode() {
        #expect(!ZoomScribeProvider.shouldTranscode(after: CloudTranscriptionError.noTranscriptionReturned))
    }

    @Test func modelNamesMatchScribeCatalog() {
        // Literal names because the test target does not link LLMkit.
        #expect(ZoomScribeProvider().models.map(\.name) == ["zoom-scribe-multilingual", "zoom-scribe-en", "zoom-scribe-en-pro"])
    }
}
