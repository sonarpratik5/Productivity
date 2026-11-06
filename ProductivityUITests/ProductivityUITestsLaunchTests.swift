import XCTest

@MainActor
final class ProductivityUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchCanOpenDashboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ProductivityUITests"]
        app.launchEnvironment = [
            "PRODUCTIVITY_UI_TESTS": "1"
        ]
        app.launch()

        let systemUIServer = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let statusItemCandidates = [
            systemUIServer.menuBars.statusItems["FocusGrove"],
            systemUIServer.menuBars.buttons["FocusGrove"],
            app.menuBars.statusItems["FocusGrove"],
            app.menuBars.buttons["FocusGrove"],
            app.buttons["FocusGroveMenuBarItem"],
            app.images["FocusGroveMenuBarItem"]
        ]

        guard let statusItem = statusItemCandidates.first(where: { $0.waitForExistence(timeout: 1) }) else {
            throw XCTSkip("The FocusGrove menu bar status item is not exposed to XCUIAutomation on this macOS session.")
        }

        statusItem.click()
        let openDashboardButton = app.buttons["MenuBarOpenDashboardButton"].exists
            ? app.buttons["MenuBarOpenDashboardButton"]
            : app.buttons["Open Dashboard"]
        XCTAssertTrue(openDashboardButton.waitForExistence(timeout: 3), app.debugDescription)
        openDashboardButton.click()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["SidebarToday"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Today"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Dashboard Launch"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.terminate()
    }
}
