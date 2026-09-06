import XCTest

final class ScreenshotUITests: XCTestCase {
    private var shotDir: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment["CALMILES_SCREENSHOT_DIR"]
            ?? "/Users/matt/Developer/Calmiles-assets/screenshots/iphone67"
        shotDir = URL(fileURLWithPath: env)
        try FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
    }

    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestSeedTrips", "-UITesting"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Calmiles"].waitForExistence(timeout: 12))
        _ = app.staticTexts["Recent"].waitForExistence(timeout: 6)
        _ = app.staticTexts["3"].waitForExistence(timeout: 6)
        sleep(1)
        save(app, "01-home-trips")

        let upgrade = app.buttons["Upgrade"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 5))
        upgrade.tap()
        XCTAssertTrue(app.staticTexts["Calmiles Pro"].waitForExistence(timeout: 5))
        _ = app.staticTexts["$9.99"].waitForExistence(timeout: 5)
        sleep(1)
        save(app, "06-paywall")
        let paywallURL = shotDir.appendingPathComponent("06-paywall.png")
        let reviewDir = URL(fileURLWithPath: "/Users/matt/Developer/Calmiles-assets/screenshots/review")
        try? FileManager.default.createDirectory(at: reviewDir, withIntermediateDirectories: true)
        let dest = reviewDir.appendingPathComponent("paywall-review.png")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: paywallURL, to: dest)
        app.buttons["Close"].tap()
        sleep(1)

        app.tabBars.buttons["Trips"].tap()
        XCTAssertTrue(app.navigationBars["Trips"].waitForExistence(timeout: 5))
        sleep(1)
        save(app, "02-trips-list")

        // Tap purpose text (not classification chip)
        let purpose = app.staticTexts["Client visit"]
        XCTAssertTrue(purpose.waitForExistence(timeout: 5))
        purpose.tap()
        if !app.navigationBars["Trip"].waitForExistence(timeout: 3) {
            // Fallback: double-tap row via accessibility element
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Business trip'")).firstMatch
            if row.exists { row.tap() }
        }
        XCTAssertTrue(app.navigationBars["Trip"].waitForExistence(timeout: 5))
        sleep(1)
        save(app, "03-classify")
        if app.buttons["Personal"].waitForExistence(timeout: 2) {
            app.buttons["Personal"].tap()
            sleep(1)
            save(app, "03b-classify-personal")
            app.buttons["Business"].tap()
            sleep(1)
            save(app, "03c-classify-business")
        }
        app.navigationBars["Trip"].buttons.firstMatch.tap()
        sleep(1)

        app.tabBars.buttons["Export"].tap()
        sleep(1)
        save(app, "04-export")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        sleep(1)
        save(app, "05-settings")
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let url = shotDir.appendingPathComponent("\(name).png")
        do {
            try shot.pngRepresentation.write(to: url)
            NSLog("WROTE \(url.path)")
        } catch {
            XCTFail("Failed to write screenshot \(name): \(error)")
        }
    }
}
