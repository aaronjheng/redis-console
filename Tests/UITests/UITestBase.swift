import XCTest

enum UITestHelper {
    static let app: XCUIApplication = {
        DispatchQueue.main.sync { XCUIApplication() }
    }()

    static func launchApp() {
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    static func addConnection(
        name: String = "Test Redis",
        host: String = "127.0.0.1",
        port: String = "6379"
    ) {
        let addButton = app.buttons["addConnectionButton"]
        if addButton.waitForExistence(timeout: 5) {
            addButton.click()
        }

        let nameField = app.textFields["connectionName"]
        if nameField.waitForExistence(timeout: 5) {
            nameField.click()
            nameField.typeText(name)
        }

        let hostField = app.textFields["connectionHost"]
        if hostField.waitForExistence(timeout: 3) {
            hostField.click()
            let currentValue = hostField.value as? String ?? ""
            if !currentValue.isEmpty {
                hostField.typeText(
                    String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
            }
            hostField.typeText(host)
        }

        let portField = app.textFields["connectionPort"]
        if portField.waitForExistence(timeout: 3) {
            portField.click()
            let currentValue = portField.value as? String ?? ""
            if !currentValue.isEmpty {
                portField.typeText(
                    String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
            }
            portField.typeText(port)
        }
    }

    static func connectToRedis(
        name: String = "Test Redis",
        host: String = "127.0.0.1",
        port: String = "6379"
    ) {
        addConnection(name: name, host: host, port: port)

        let connectButton = app.buttons["connectButton"]
        if connectButton.waitForExistence(timeout: 5) {
            connectButton.click()
        }

        waitForConnection()
    }

    static func waitForConnection(timeout: TimeInterval = 15) {
        let disconnectButton = app.buttons["disconnectButton"]
        let connected = disconnectButton.waitForExistence(timeout: timeout)
        XCTAssertTrue(connected, "Failed to connect to Redis within \(timeout)s")
    }

    static func disconnect() {
        let disconnectButton = app.buttons["disconnectButton"]
        if disconnectButton.exists {
            disconnectButton.click()
        }
    }

    static func navigateToBrowser() {
        navigateTo(tool: "Browser")
    }

    static func navigateToShell() {
        navigateTo(tool: "Shell")
    }

    static func navigateToSlowLog() {
        navigateTo(tool: "Slow Log")
    }

    static func navigateToServerInfo() {
        navigateTo(tool: "Server Info")
    }

    private static func navigateTo(tool: String) {
        let toolsList = app.groups["toolsList"]
        if toolsList.waitForExistence(timeout: 5) {
            let toolItem = toolsList.staticTexts[tool]
            if toolItem.exists {
                toolItem.click()
            }
        }
    }

    static func executeShellCommand(_ command: String) {
        let shellInput = app.textFields["shellInput"]
        if shellInput.waitForExistence(timeout: 5) {
            shellInput.click()
            shellInput.typeText(command + "\r")
        }
    }

    static func cleanupTestKeys() {
        navigateToShell()
        executeShellCommand("DEL test_uitest_string")
        executeShellCommand("DEL test_uitest_hash")
        executeShellCommand("DEL test_uitest_list")
        executeShellCommand("DEL test_uitest_set")
        executeShellCommand("DEL test_uitest_zset")
        sleep(1)
    }
}

struct RedisTestConfig: Sendable {
    let name: String
    let host: String
    let port: String

    static let redis6Standalone = RedisTestConfig(
        name: "Redis 6 Standalone", host: "127.0.0.1", port: "6376")
    static let redis7Standalone = RedisTestConfig(
        name: "Redis 7 Standalone", host: "127.0.0.1", port: "6377")
    static let redis8Standalone = RedisTestConfig(
        name: "Redis 8 Standalone", host: "127.0.0.1", port: "6378")
}
