import Testing

@testable import VoiceInk

// Only the pure enum logic is covered here. `ModeValidator.validateForSave`
// itself needs a live `ModeManager` (a strict singleton — `private init()`),
// so it isn't safely unit-testable without touching real global app state.
// Worth revisiting if ModeManager ever gets a protocol/DI seam.
struct ModeValidationErrorTests {

    @Test func idsAreStableAndDistinctPerCase() {
        let errors: [ModeValidationError] = [
            .emptyName,
            .emptyCustomCommand,
            .duplicateName("x"),
            .duplicateAppTrigger("app", "mode"),
            .duplicateWebsiteTrigger("site", "mode"),
        ]
        #expect(Set(errors.map(\.id)).count == errors.count)
    }

    @Test func duplicateNameMessageIncludesTheName() {
        let error = ModeValidationError.duplicateName("Coding")
        #expect(error.localizedDescription.contains("Coding"))
    }

    @Test func duplicateAppTriggerMessageIncludesBothNames() {
        let error = ModeValidationError.duplicateAppTrigger("Slack", "Chat Mode")
        #expect(error.localizedDescription.contains("Slack"))
        #expect(error.localizedDescription.contains("Chat Mode"))
    }

    @Test func duplicateWebsiteTriggerMessageIncludesBothNames() {
        let error = ModeValidationError.duplicateWebsiteTrigger("slack.com", "Chat Mode")
        #expect(error.localizedDescription.contains("slack.com"))
        #expect(error.localizedDescription.contains("Chat Mode"))
    }
}
