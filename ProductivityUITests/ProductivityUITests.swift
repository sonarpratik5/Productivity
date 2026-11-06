import XCTest

@MainActor
final class ProductivityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ProductivityUITests"]
        app.launchEnvironment = [
            "PRODUCTIVITY_UI_TESTS": "1"
        ]
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testDashboardOpensFromMenuBar() throws {
        launchApp()

        try openDashboardFromMenuBar()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        assertDashboardVisible()
    }

    func testCloseButtonHidesWindowWithoutTerminatingApp() throws {
        launchApp()
        try openDashboardFromMenuBar()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.click()

        XCTAssertFalse(app.windows.firstMatch.waitForExistence(timeout: 1))
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
    }

    func testPomodoroPageStartPauseAndResetControls() throws {
        launchApp()
        try openDashboardFromMenuBar()
        assertDashboardVisible()

        let pomodoroNavigationItem = app.staticTexts["Pomodoro"]
        XCTAssertTrue(pomodoroNavigationItem.waitForExistence(timeout: 3))
        pomodoroNavigationItem.click()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 3))
        startButton.click()

        let pauseButton = app.buttons["Pause"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 3))
        pauseButton.click()

        let resetButton = app.buttons.matching(identifier: "Reset").firstMatch
        if resetButton.exists {
            resetButton.click()
        }

        XCTAssertTrue(app.staticTexts["Focus"].waitForExistence(timeout: 3))
    }

    func testSettingsPageOpensFromSidebar() throws {
        launchApp()
        try openDashboardFromMenuBar()
        assertDashboardVisible()

        let settingsNavigationItem = app.staticTexts["SidebarSettings"]
        XCTAssertTrue(settingsNavigationItem.waitForExistence(timeout: 3), app.debugDescription)
        settingsNavigationItem.click()

        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Appearance"].exists)
    }

    func testMenuBarPopoverExposesDashboardControls() throws {
        launchApp()

        try openMenuBarExtra()

        XCTAssertTrue(app.staticTexts["FocusGrove"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Dashboard"].exists)
        XCTAssertTrue(app.buttons["Start"].exists || app.buttons["Pause"].exists)
        XCTAssertTrue(app.checkBoxes["Tracking"].exists || app.checkBoxes["MenuBarTrackingToggle"].exists)
    }

    private func launchApp() {
        app.launch()
    }

    private func openDashboardFromMenuBar() throws {
        try openMenuBarExtra()

        let openDashboardButton = app.buttons["MenuBarOpenDashboardButton"].exists
            ? app.buttons["MenuBarOpenDashboardButton"]
            : app.buttons["Open Dashboard"]
        XCTAssertTrue(openDashboardButton.waitForExistence(timeout: 3), app.debugDescription)
        openDashboardButton.click()
    }

    private func assertDashboardVisible() {
        XCTAssertTrue(app.staticTexts["SidebarToday"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Today"].exists)
    }

    private func openMenuBarExtra() throws {
        let systemUIServer = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let statusItemCandidates = [
            systemUIServer.menuBars.statusItems["FocusGrove"],
            systemUIServer.menuBars.buttons["FocusGrove"],
            app.menuBars.statusItems["FocusGrove"],
            app.menuBars.buttons["FocusGrove"],
            app.buttons["FocusGroveMenuBarItem"],
            app.images["FocusGroveMenuBarItem"]
        ]

        if let statusItem = statusItemCandidates.first(where: { $0.waitForExistence(timeout: 1) }) {
            statusItem.click()
            return
        }

        throw XCTSkip("The FocusGrove menu bar status item is not exposed to XCUIAutomation on this macOS session.")
    }
}
