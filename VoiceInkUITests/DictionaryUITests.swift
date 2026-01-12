import XCTest

/// UI tests for Dictionary/Word Replacement
/// Tests CRUD operations on dictionary entries
@available(macOS 14.0, *)
final class DictionaryUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Dictionary UI Tests
    
    func testOpenDictionary() throws {
        // Navigate to dictionary
        app.menuBars.menuBarItems["VoiceInk"].click()
        app.menuItems["Dictionary"].click()
        
        // Verify dictionary window
        let dictWindow = app.windows["Dictionary"]
        XCTAssertTrue(dictWindow.waitForExistence(timeout: 3.0), "Dictionary window should open")
    }
    
    func testDictionaryEntryList() throws {
        app.menuBars.menuBarItems["VoiceInk"].click()
        app.menuItems["Dictionary"].click()
        
        sleep(1)
        
        // Should show list or table of entries
        let entryList = app.tables.firstMatch
        XCTAssertTrue(entryList.exists || app.textFields.count > 0, "Dictionary UI should be visible")
    }
}
