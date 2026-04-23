import XCTest

final class ShellTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        UITestHelper.launchApp()
        UITestHelper.connectToRedis()
        UITestHelper.navigateToShell()
    }

    override func tearDownWithError() throws {
        UITestHelper.navigateToShell()
        UITestHelper.executeShellCommand("DEL test_uitest_shell_key")
        sleep(1)
        try super.tearDownWithError()
    }

    func testExecutePing() {
        UITestHelper.executeShellCommand("PING")

        let historyText = UITestHelper.app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS 'PONG'")
        ).firstMatch
        let found = historyText.waitForExistence(timeout: 10)
        XCTAssertTrue(found, "PING should return PONG")
    }

    func testExecuteSetAndGet() {
        UITestHelper.executeShellCommand("SET test_uitest_shell_key hello")
        sleep(1)
        UITestHelper.executeShellCommand("GET test_uitest_shell_key")

        let historyText = UITestHelper.app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS 'hello'")
        ).firstMatch
        let found = historyText.waitForExistence(timeout: 10)
        XCTAssertTrue(found, "GET should return the value set by SET")
    }

    func testInvalidCommand() {
        UITestHelper.executeShellCommand("INVALIDCOMMAND")

        let errorText = UITestHelper.app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS 'error' OR value CONTAINS 'ERR'")
        ).firstMatch
        let found = errorText.waitForExistence(timeout: 10)
        XCTAssertTrue(found, "Invalid command should produce an error")
    }

    func testCommandHistory() {
        UITestHelper.executeShellCommand("SET test_uitest_shell_key history_test")
        sleep(1)
        UITestHelper.executeShellCommand("GET test_uitest_shell_key")
        sleep(1)

        let shellInput = UITestHelper.app.textFields["shellInput"]
        XCTAssertTrue(shellInput.waitForExistence(timeout: 5))
        shellInput.click()
        shellInput.typeKey(.upArrow, modifierFlags: [])
        sleep(1)

        let value = shellInput.value as? String ?? ""
        XCTAssertTrue(value.contains("GET") || value.contains("get"), "Up arrow should recall last command")
    }
}

final class ShellTestsRedis6: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        UITestHelper.launchApp()
        UITestHelper.connectToRedis(
            name: RedisTestConfig.redis6Standalone.name,
            host: RedisTestConfig.redis6Standalone.host,
            port: RedisTestConfig.redis6Standalone.port)
        UITestHelper.navigateToShell()
    }

    func testExecutePing() {
        UITestHelper.executeShellCommand("PING")
        let historyText = UITestHelper.app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS 'PONG'")
        ).firstMatch
        XCTAssertTrue(historyText.waitForExistence(timeout: 10))
    }
}

final class ShellTestsRedis8: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        UITestHelper.launchApp()
        UITestHelper.connectToRedis(
            name: RedisTestConfig.redis8Standalone.name,
            host: RedisTestConfig.redis8Standalone.host,
            port: RedisTestConfig.redis8Standalone.port)
        UITestHelper.navigateToShell()
    }

    func testExecutePing() {
        UITestHelper.executeShellCommand("PING")
        let historyText = UITestHelper.app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS 'PONG'")
        ).firstMatch
        XCTAssertTrue(historyText.waitForExistence(timeout: 10))
    }
}
