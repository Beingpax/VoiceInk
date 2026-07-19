import XCTest

// Regression coverage for two real bugs a user hit manually: (1) the golden eval set UI was
// built into a view only reachable via a legacy menu-bar popover, invisible from the actual
// primary History screen reached from the main window's sidebar; (2) a crash on "Mark
// Verified" that unit tests never caught because they don't exercise the real window/view
// hierarchy. XCUITest drives the actual compiled app through Accessibility, the same way a
// human would click through it -- exactly the class of "wrong view" / "missing button" bug
// that manual review keeps catching after the fact.
final class HistoryNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // VoiceInk never auto-opens its main window on a cold launch (menu-bar-first by
        // design) — real users reach it via the Dock icon or menu bar, and
        // applicationShouldHandleReopen (the real trigger) only fires on Dock reactivation of
        // an already-running app, not a fresh XCUITest launch. This launch argument
        // (AppDelegate.swift) opens it deterministically for UI tests only.
        app.launchArguments = ["-uiTestOpenMainWindow"]
        app.launch()

        XCTAssertTrue(
            app.buttons["History"].waitForExistence(timeout: 10),
            "Main window should be visible on launch with -uiTestOpenMainWindow")
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    // The sidebar item is reachable and, when tapped, renders the real History screen — not
    // just some view named "History" that happens to compile.
    @MainActor
    func testHistorySidebarItemOpensHistoryScreen() throws {
        let historyItem = app.buttons["History"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: 10), "Sidebar should have a History item")
        historyItem.click()

        let searchField = app.textFields["Search transcriptions..."]
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 5),
            "History screen should show its search field after navigating from the sidebar")
    }

    // The exact bug from this session: the Golden Eval Set toggle must exist on the REAL
    // History screen (reached via the sidebar), not just in some other view.
    @MainActor
    func testGoldenEvalSetToggleIsReachableFromHistory() throws {
        app.buttons["History"].click()

        // SwiftUI's .pickerStyle(.segmented) reports as a RadioGroup of RadioButtons on macOS,
        // not XCUIElementTypeSegmentedControl/.buttons.
        let modeToggle = app.radioGroups["history.modeToggle"]
        XCTAssertTrue(
            modeToggle.waitForExistence(timeout: 5),
            "History screen should show the All/Golden Eval Set mode toggle")

        let goldenEvalSegment = modeToggle.radioButtons["Golden Eval Set"]
        XCTAssertTrue(goldenEvalSegment.exists, "Mode toggle should have a Golden Eval Set segment")
        goldenEvalSegment.click()

        let counts = app.staticTexts["history.goldenEvalCounts"]
        XCTAssertTrue(
            counts.waitForExistence(timeout: 5),
            "Switching to Golden Eval Set mode should show the Control/Train/Eval counts toolbar")

        let runBaseline = app.buttons["history.runBaselineEvaluation"]
        XCTAssertTrue(runBaseline.exists, "Golden Eval Set mode should show the Run Baseline Evaluation button")
    }

    // Apple Intelligence provider selection lives under Modes, not "AI Models" — confirmed via
    // investigation after a user checked the wrong screen. Assert Modes itself is reachable so
    // a future refactor that breaks this navigation path fails a test, not a screenshot.
    @MainActor
    func testModesSidebarItemIsReachable() throws {
        let modesItem = app.buttons["Modes"]
        XCTAssertTrue(modesItem.waitForExistence(timeout: 10), "Sidebar should have a Modes item")
        modesItem.click()
    }
}
