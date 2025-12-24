import XCTest

/// UI tests for the onboarding flow
/// Tests first-run experience and permission requests
@available(macOS 14.0, *)
final class OnboardingUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Reset onboarding state for testing
        app.launchArguments = ["--reset-onboarding"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Onboarding Flow Tests
    
    func testOnboardingAppearsOnFirstLaunch() throws {
        // Verify onboarding appears
        let welcomeText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'welcome'")).firstMatch
        XCTAssertTrue(welcomeText.waitForExistence(timeout: 5.0), "Welcome screen should appear")
    }
    
    func testOnboardingPermissionsStep() throws {
        // Navigate to permissions step
        let continueButton = app.buttons["Continue"]
        
        if continueButton.exists {
            continueButton.tap()
            
            // Should show permissions request
            let permissionsText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'permission'")).firstMatch
            XCTAssertTrue(permissionsText.waitForExistence(timeout: 3.0), "Permissions screen should appear")
        }
    }
    
    func testOnboardingModelDownloadStep() throws {
        // Navigate through onboarding
        let continueButton = app.buttons["Continue"]
        
        // Skip through steps to model download
        for _ in 0..<3 {
            if continueButton.exists {
                continueButton.tap()
                sleep(1)
            }
        }
        
        // Should show model selection
        let modelText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'model'")).firstMatch
        XCTAssertTrue(modelText.waitForExistence(timeout: 3.0), "Model selection should appear")
    }
}
