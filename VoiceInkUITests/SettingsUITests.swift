import XCTest

/// UI tests for Settings interactions
/// Tests settings panel navigation and changes
@available(macOS 14.0, *)
final class SettingsUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Settings Access Tests
    
    func testOpenSettings() throws {
        // Open settings via menu
        app.menuBars.menuBarItems["VoiceInk"].click()
        app.menuItems["Settings"].click()
        
        // Verify settings window appears
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 3.0), "Settings window should open")
    }
    
    func testAudioInputSettings() throws {
        // Navigate to audio settings
        app.menuBars.menuBarItems["VoiceInk"].click()
        app.menuItems["Settings"].click()
        
        let audioTab = app.buttons["Audio"]
        if audioTab.exists {
            audioTab.click()
            
            // Verify audio device picker exists
            let devicePicker = app.popUpButtons.firstMatch
            XCTAssertTrue(devicePicker.exists, "Audio device picker should exist")
        }
    }
    
    func testAIEnhancementSettings() throws {
        app.menuBars.menuBarItems["VoiceInk"].click()
        app.menuItems["Settings"].click()
        
        let aiTab = app.buttons["AI Enhancement"]
        if aiTab.exists {
            aiTab.click()
            
            // Verify AI settings
            let enableToggle = app.checkBoxes.firstMatch
            XCTAssertTrue(enableToggle.exists, "AI enable toggle should exist")
        }
    }
    
    func testAPIKeySettings() throws {
        app.menuBars.menuBarItems["VoiceInk"].click()
        app.menuItems["Settings"].click()
        
        // Look for API key fields
        let secureFields = app.secureTextFields
        XCTAssertGreaterThan(secureFields.count, 0, "Should have API key fields")
    }
}
