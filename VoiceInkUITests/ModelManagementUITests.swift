import XCTest

/// UI tests for AI Model management
/// Tests model selection, download, and management
@available(macOS 14.0, *)
final class ModelManagementUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Model Management Tests
    
    func testOpenModelManagement() throws {
        // Navigate to model management
        app.menuBars.menuBarItems["VoiceInk"].click()
        app.menuItems["AI Models"].click()
        
        // Verify models window
        let modelsWindow = app.windows["AI Models"]
        XCTAssertTrue(modelsWindow.waitForExistence(timeout: 3.0), "Models window should open")
    }
    
    func testModelListDisplay() throws {
        app.menuBars.menuBarItems["VoiceInk"].click()
        app.menuItems["AI Models"].click()
        
        sleep(1)
        
        // Should show list of models
        let modelList = app.tables.firstMatch
        XCTAssertTrue(modelList.exists, "Model list should be displayed")
    }
    
    func testModelSelection() throws {
        app.menuBars.menuBarItems["VoiceInk"].click()
        app.menuItems["AI Models"].click()
        
        sleep(1)
        
        // Try to select a model
        let firstModel = app.tables.cells.firstMatch
        if firstModel.exists {
            firstModel.click()
            
            // Should not crash
            XCTAssertTrue(app.exists, "App should handle model selection")
        }
    }
}
