import Foundation
import Testing

@testable import VoiceInk

// Pins storageName/displayName/isStored for the static-array-backed actions, and — the actual
// bug class this guards against — that every stored, non-mode action is registered in BOTH
// globalUtilityActions (or its own dispatch path) and legacyKeyboardShortcutActions (used for
// conflict detection, despite the name). Forgetting one is a silent runtime miss, not a
// compile error, which is exactly what happened while adding flagLastTranscription.
struct ShortcutActionTests {

    @Test func flagLastTranscriptionHasAStableStorageName() {
        #expect(ShortcutAction.flagLastTranscription.storageName == "flagLastTranscription")
        #expect(ShortcutAction.flagLastTranscription.isStored == true)
    }

    @Test func flagLastTranscriptionIsRegisteredAsAGlobalUtilityAction() {
        #expect(ShortcutAction.globalUtilityActions.contains(.flagLastTranscription))
    }

    @Test func flagLastTranscriptionParticipatesInConflictDetection() {
        #expect(ShortcutAction.legacyKeyboardShortcutActions.contains(.flagLastTranscription))
    }

    @Test func recorderPanelActionsAreNotStored() {
        #expect(ShortcutAction.recorderPanelEscape.isStored == false)
        #expect(ShortcutAction.recorderPanelMode(0).isStored == false)
    }
}
