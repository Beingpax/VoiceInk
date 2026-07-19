import Foundation
import Testing

@testable import VoiceInk

// Serialized — these tests each hit the shared macOS preferences daemon
// (cfprefsd) via UserDefaults(suiteName:), and running them concurrently
// (Swift Testing's default within a suite, independent of xcodebuild's
// -parallel-testing-enabled flag, which only controls device/process-level
// parallelism) caused a genuine flake on GitHub's CI runner.
@Suite(.serialized)
struct PasteMethodTests {

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PasteMethodTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.synchronize()
        return defaults
    }

    @Test func defaultsToStandardWhenNothingStored() {
        let defaults = isolatedDefaults()
        #expect(PasteMethod.current(in: defaults) == .standard)
    }

    @Test func setCurrentPersistsAndRoundTrips() {
        let defaults = isolatedDefaults()
        PasteMethod.setCurrent(.appleScript, in: defaults)
        #expect(PasteMethod.current(in: defaults) == .appleScript)

        PasteMethod.setCurrent(.standard, in: defaults)
        #expect(PasteMethod.current(in: defaults) == .standard)
    }

    @Test func migratesLegacyAppleScriptFlagWhenNoModernKeyExists() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: PasteMethod.legacyAppleScriptPasteKey)

        PasteMethod.migrateLegacyUserDefaultIfNeeded(in: defaults)

        #expect(PasteMethod.current(in: defaults) == .appleScript)
        #expect(defaults.string(forKey: PasteMethod.userDefaultsKey) == PasteMethod.appleScript.rawValue)
    }

    @Test func migrationIsANoOpWhenModernKeyAlreadyExists() {
        let defaults = isolatedDefaults()
        PasteMethod.setCurrent(.standard, in: defaults)
        defaults.set(true, forKey: PasteMethod.legacyAppleScriptPasteKey)  // stale legacy flag
        defaults.synchronize()  // force the writes visible before reading them back below

        PasteMethod.migrateLegacyUserDefaultIfNeeded(in: defaults)

        // Modern key already existed — migration must not override it with the stale legacy flag.
        #expect(PasteMethod.current(in: defaults) == .standard)
    }
}
