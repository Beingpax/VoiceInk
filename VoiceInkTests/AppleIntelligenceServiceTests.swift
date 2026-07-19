import Testing

@testable import VoiceInk

struct AppleIntelligenceServiceTests {

    @Test func unavailableErrorDescriptionIncludesReason() {
        let error = AppleIntelligenceService.AppleIntelligenceError.unavailable("Device not eligible.")

        #expect(error.errorDescription?.contains("Device not eligible.") == true)
        #expect(error.errorDescription?.contains("Apple Intelligence is unavailable") == true)
    }

    @Test func unavailableReasonIsNilExactlyWhenAvailable() {
        // Real invariant, not a hardcoded expectation about this machine's Apple Intelligence
        // state: whatever `isAvailable` resolves to on the current OS/device, `unavailableReason`
        // must agree with it. Catches the two falling out of sync if either is edited later.
        let isAvailable = AppleIntelligenceService.isAvailable
        let reason = AppleIntelligenceService.unavailableReason

        #expect((reason == nil) == isAvailable)
    }

    @Test func unavailableReasonIsNonEmptyWhenUnavailable() {
        guard !AppleIntelligenceService.isAvailable else { return }

        let reason = AppleIntelligenceService.unavailableReason
        #expect(reason?.isEmpty == false)
    }

    @Test func enhanceThrowsWhenUnavailable() async {
        guard !AppleIntelligenceService.isAvailable else { return }

        await #expect(throws: AppleIntelligenceService.AppleIntelligenceError.self) {
            _ = try await AppleIntelligenceService.enhance(text: "hello", systemPrompt: "")
        }
    }
}
