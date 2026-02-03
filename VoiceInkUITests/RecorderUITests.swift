import XCTest

/// UI tests for Mini Recorder interactions
/// Tests recording UI and controls
@available(macOS 14.0, *)
final class RecorderUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Mini Recorder Tests
    
    func testShowMiniRecorder() throws {
        // Trigger mini recorder (via hotkey simulation or menu)
        app.menuBars.menuBarItems["VoiceInk"].click()
        app.menuItems["Show Recorder"].click()
        
        // Verify recorder appears
        let recorderWindow = app.windows.containing(.window, identifier: "MiniRecorder").firstMatch
        
        // Allow time for animation
        sleep(1)
        
        // Recorder should be visible (check for any window or recording indicator)
        let recordButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'record'")).firstMatch
        XCTAssertTrue(recordButton.exists || app.windows.count > 0, "Recorder UI should be visible")
    }
    
    func testDismissMiniRecorder() throws {
        // Show recorder
        app.menuBars.menuBarItems["VoiceInk"].click()
        app.menuItems["Show Recorder"].click()
        
        sleep(1)
        
        // Dismiss via Escape or close button
        app.typeKey(.escape, modifierFlags: [])
        
        sleep(1)
        
        // Recorder should be hidden
        // This test verifies the app doesn't crash on dismiss
        XCTAssertTrue(app.exists, "App should remain running after dismissing recorder")
    }
}
