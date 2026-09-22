import Foundation
import XCTest
@testable import VoiceInk

final class GeminiTranscriptionSettingsTests: XCTestCase {
    func testDefaultsToVerbatim() {
        withDefaults { defaults in
            XCTAssertEqual(GeminiTranscriptionSettings.mode(defaults: defaults).rawValue, "verbatim")
        }
    }

    func testToggleSelectsSmartAndCanReturnToVerbatim() {
        withDefaults { defaults in
            defaults.set(true, forKey: GeminiTranscriptionSettings.smartTranscriptionKey)
            XCTAssertEqual(GeminiTranscriptionSettings.mode(defaults: defaults).rawValue, "smart")

            defaults.set(false, forKey: GeminiTranscriptionSettings.smartTranscriptionKey)
            XCTAssertEqual(GeminiTranscriptionSettings.mode(defaults: defaults).rawValue, "verbatim")
        }
    }

    func testSelectionPersistsAcrossDefaultsInstances() {
        let suiteName = "GeminiTranscriptionSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: GeminiTranscriptionSettings.smartTranscriptionKey)

        let reloadedDefaults = UserDefaults(suiteName: suiteName)!
        XCTAssertEqual(GeminiTranscriptionSettings.mode(defaults: reloadedDefaults).rawValue, "smart")
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "GeminiTranscriptionSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
