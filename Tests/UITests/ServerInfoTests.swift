import XCTest

final class ServerInfoTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        UITestHelper.launchApp()
        UITestHelper.connectToRedis()
    }

    func testViewServerInfo() {
        UITestHelper.navigateToServerInfo()

        let refreshButton = UITestHelper.app.buttons["refreshServerInfo"]
        XCTAssertTrue(
            refreshButton.waitForExistence(timeout: 5),
            "Server Info view should be visible with refresh button")

        let listSection = UITestHelper.app.scrollViews.firstMatch
        let infoLoaded = listSection.waitForExistence(timeout: 10)
        XCTAssertTrue(infoLoaded, "Server info sections should load")
    }

    func testRefreshServerInfo() {
        UITestHelper.navigateToServerInfo()

        let refreshButton = UITestHelper.app.buttons["refreshServerInfo"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5))
        refreshButton.click()

        sleep(2)

        let listSection = UITestHelper.app.scrollViews.firstMatch
        XCTAssertTrue(listSection.waitForExistence(timeout: 10), "Server info should refresh and load")
    }

    func testViewSlowLog() {
        UITestHelper.navigateToSlowLog()

        let slowLogHeader = UITestHelper.app.staticTexts["Slow Log"]
        XCTAssertTrue(
            slowLogHeader.waitForExistence(timeout: 5),
            "Slow Log view should be visible")
    }

    func testLoadSlowLog() {
        UITestHelper.navigateToSlowLog()

        let refreshButton = UITestHelper.app.buttons["refreshSlowLogButton"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5), "Slow Log refresh button should exist")
        refreshButton.click()

        sleep(2)

        let slowLogHeader = UITestHelper.app.staticTexts["Slow Log"]
        XCTAssertTrue(slowLogHeader.exists, "Slow Log view should remain visible after refresh")
    }
}

final class ServerInfoTestsRedis6: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        UITestHelper.launchApp()
        UITestHelper.connectToRedis(
            name: RedisTestConfig.redis6Standalone.name,
            host: RedisTestConfig.redis6Standalone.host,
            port: RedisTestConfig.redis6Standalone.port)
    }

    func testViewServerInfo() {
        UITestHelper.navigateToServerInfo()
        let refreshButton = UITestHelper.app.buttons["refreshServerInfo"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5))
    }
}

final class ServerInfoTestsRedis8: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        UITestHelper.launchApp()
        UITestHelper.connectToRedis(
            name: RedisTestConfig.redis8Standalone.name,
            host: RedisTestConfig.redis8Standalone.host,
            port: RedisTestConfig.redis8Standalone.port)
    }

    func testViewServerInfo() {
        UITestHelper.navigateToServerInfo()
        let refreshButton = UITestHelper.app.buttons["refreshServerInfo"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5))
    }
}
