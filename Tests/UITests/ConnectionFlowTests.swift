import XCTest

final class ConnectionFlowTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        UITestHelper.launchApp()
    }

    func testNewConnectionFormAppears() {
        let addButton = UITestHelper.app.buttons["addConnectionButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.click()

        XCTAssertTrue(UITestHelper.app.textFields["connectionName"].waitForExistence(timeout: 3))
        XCTAssertTrue(UITestHelper.app.textFields["connectionHost"].waitForExistence(timeout: 3))
        XCTAssertTrue(UITestHelper.app.textFields["connectionPort"].waitForExistence(timeout: 3))
        XCTAssertTrue(UITestHelper.app.textFields["connectionUsername"].waitForExistence(timeout: 3))
        XCTAssertTrue(UITestHelper.app.secureTextFields["connectionPassword"].waitForExistence(timeout: 3))
        XCTAssertTrue(UITestHelper.app.buttons["connectButton"].waitForExistence(timeout: 3))
    }

    func testSaveConnection() {
        UITestHelper.addConnection(name: "Saved Connection", host: "127.0.0.1")

        let saveButton = UITestHelper.app.buttons["saveConnectionButton"]
        if saveButton.waitForExistence(timeout: 5) {
            saveButton.click()
        }

        let connectionList = UITestHelper.app.groups["connectionList"]
        XCTAssertTrue(connectionList.waitForExistence(timeout: 5))
    }

    func testTestConnection() {
        UITestHelper.addConnection(name: "Test Conn", host: "127.0.0.1")

        let testButton = UITestHelper.app.buttons["testConnectionButton"]
        if testButton.waitForExistence(timeout: 5) {
            testButton.click()
        }

        let testResult = UITestHelper.app.groups["testResult"]
        let resultAppeared = testResult.waitForExistence(timeout: 15)
        XCTAssertTrue(resultAppeared, "Test connection result should appear")
    }

    func testConnectAndDisconnect() {
        UITestHelper.connectToRedis()

        let disconnectButton = UITestHelper.app.buttons["disconnectButton"]
        XCTAssertTrue(disconnectButton.exists, "Should be connected")

        disconnectButton.click()

        let addButton = UITestHelper.app.buttons["addConnectionButton"]
        XCTAssertTrue(
            addButton.waitForExistence(timeout: 5),
            "Should be disconnected and show add button")
    }

    func testConnectionFailure() {
        UITestHelper.addConnection(name: "Bad Host", host: "255.255.255.1", port: "19999")

        let connectButton = UITestHelper.app.buttons["connectButton"]
        if connectButton.waitForExistence(timeout: 5) {
            connectButton.click()
        }

        let addButton = UITestHelper.app.buttons["addConnectionButton"]
        let returnedToDisconnected = addButton.waitForExistence(timeout: 15)
        XCTAssertTrue(
            returnedToDisconnected,
            "Should return to disconnected state after failed connection")
    }

    func testImportFromURI() {
        let addButton = UITestHelper.app.buttons["addConnectionButton"]
        if addButton.waitForExistence(timeout: 5) {
            addButton.click()
        }

        let uriField = UITestHelper.app.textFields["uriInput"]
        if uriField.waitForExistence(timeout: 5) {
            uriField.click()
            uriField.typeText("redis://myuser:mypass@10.0.0.1:6380")
        }

        let importButton = UITestHelper.app.buttons["Import"]
        if importButton.waitForExistence(timeout: 3) {
            importButton.click()
        }

        let hostField = UITestHelper.app.textFields["connectionHost"]
        if hostField.waitForExistence(timeout: 3) {
            let hostValue = hostField.value as? String ?? ""
            XCTAssertEqual(hostValue, "10.0.0.1", "Host should be imported from URI")
        }
    }

    func testEditExistingConnection() {
        UITestHelper.addConnection(name: "Edit Me", host: "127.0.0.1", port: "6379")

        let saveButton = UITestHelper.app.buttons["saveConnectionButton"]
        if saveButton.waitForExistence(timeout: 5) {
            saveButton.click()
        }

        let connectionList = UITestHelper.app.groups["connectionList"]
        XCTAssertTrue(connectionList.waitForExistence(timeout: 5))

        let connectionRow = connectionList.staticTexts["Edit Me"]
        if connectionRow.waitForExistence(timeout: 5) {
            connectionRow.click()
        }

        let nameField = UITestHelper.app.textFields["connectionName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Name field should appear for editing")

        nameField.click()
        let currentValue = nameField.value as? String ?? ""
        if !currentValue.isEmpty {
            nameField.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }
        nameField.typeText("Edited Name")

        let saveEditedButton = UITestHelper.app.buttons["saveConnectionButton"]
        if saveEditedButton.waitForExistence(timeout: 5) {
            saveEditedButton.click()
        }

        let editedRow = connectionList.staticTexts["Edited Name"]
        XCTAssertTrue(editedRow.waitForExistence(timeout: 5), "Edited connection should appear in list")
    }
}
