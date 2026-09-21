import XCTest

final class CalmilesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingLaunchSmoke() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestReset"]
        app.launch()
        // Onboarding title or main tab should appear
        let calmiles = app.staticTexts["Calmiles"]
        XCTAssertTrue(calmiles.waitForExistence(timeout: 5))
    }
}
