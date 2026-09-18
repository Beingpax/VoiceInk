import SwiftData
import XCTest
@testable import VoiceInk

@MainActor
final class DictionarySmokeTests: XCTestCase {
    func testExistingWordReplacementStillRuns() throws {
        let schema = Schema([WordReplacement.self])
        let configuration = ModelConfiguration("dictionary", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        context.insert(WordReplacement(originalText: "web socket", replacementText: "WebSocket"))
        try context.save()

        let result = WordReplacementService.shared.applyReplacements(
            to: "The web socket is open.", using: context
        )

        XCTAssertEqual(result, "The WebSocket is open.")
    }
}
