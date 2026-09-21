import XCTest

/// Drives a continuous ~20s in-app journey for App Store App Preview recording.
/// Launch with: -UITestAppPreview -UITestSkipOnboarding -UITestSeedTrips
final class AppPreviewUITests: XCTestCase {
    func testRecordAppPreviewJourney() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestAppPreview",
            "-UITestSkipOnboarding",
            "-UITestSeedTrips",
        ]
        app.launch()

        // Splash (~1.5s) then home
        XCTAssertTrue(app.navigationBars["Calmiles"].waitForExistence(timeout: 8))
        _ = app.staticTexts["Recent"].waitForExistence(timeout: 3)
        sleep(1)

        // Paywall briefly
        let upgrade = app.buttons["Upgrade"]
        if upgrade.waitForExistence(timeout: 2) {
            upgrade.tap()
            _ = app.staticTexts["Calmiles Pro"].waitForExistence(timeout: 3)
            sleep(1)
            if app.buttons["Close"].waitForExistence(timeout: 2) {
                app.buttons["Close"].tap()
            }
            usleep(400_000)
        }

        // Trips list
        app.tabBars.buttons["Trips"].tap()
        XCTAssertTrue(app.navigationBars["Trips"].waitForExistence(timeout: 4))
        sleep(1)

        // Classify
        let purpose = app.staticTexts["Client visit"]
        if purpose.waitForExistence(timeout: 3) {
            purpose.tap()
        } else {
            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] 'Business'")).firstMatch
            if row.exists { row.tap() }
        }
        XCTAssertTrue(app.navigationBars["Trip"].waitForExistence(timeout: 4))
        sleep(1)
        if app.buttons["Personal"].waitForExistence(timeout: 2) {
            app.buttons["Personal"].tap()
            usleep(500_000)
            app.buttons["Business"].tap()
            usleep(500_000)
        }
        app.navigationBars["Trip"].buttons.firstMatch.tap()
        usleep(400_000)

        // Export
        app.tabBars.buttons["Export"].tap()
        sleep(1)

        // Settings
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 4))
        sleep(1)

        // End on home
        app.tabBars.buttons["Home"].tap()
        _ = app.navigationBars["Calmiles"].waitForExistence(timeout: 3)
        usleep(600_000)
    }
}
