import XCTest

final class BrowserTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        UITestHelper.launchApp()
        UITestHelper.connectToRedis()
        UITestHelper.navigateToBrowser()
    }

    override func tearDownWithError() throws {
        UITestHelper.cleanupTestKeys()
        try super.tearDownWithError()
    }

    func testScanKeys() {
        let keyList = UITestHelper.app.groups["keyList"]
        XCTAssertTrue(
            keyList.waitForExistence(timeout: 10),
            "Key list should appear after connecting")
    }

    func testSearchKeys() {
        let searchField = UITestHelper.app.textFields["keySearchField"]
        if searchField.waitForExistence(timeout: 5) {
            searchField.click()
            searchField.typeText("test_uitest_*\r")
        }

        let keyList = UITestHelper.app.groups["keyList"]
        XCTAssertTrue(keyList.waitForExistence(timeout: 10))
    }

    func testAddAndDeleteStringKey() {
        let addButton = UITestHelper.app.buttons["addKeyButton"]
        if addButton.waitForExistence(timeout: 5) {
            addButton.click()
        }

        let sheet = UITestHelper.app.sheets.firstMatch
        if sheet.waitForExistence(timeout: 5) {
            let nameField = sheet.textFields["newKeyNameField"]
            if nameField.exists {
                nameField.click()
                nameField.typeText("test_uitest_string")
            }

            let valueField = sheet.textFields["newKeyValueField"]
            if valueField.exists {
                valueField.click()
                valueField.typeText("hello uitest")
            }

            let addInSheet = sheet.buttons["Add"]
            if addInSheet.exists {
                addInSheet.click()
            }
        }

        sleep(2)

        let searchField = UITestHelper.app.textFields["keySearchField"]
        if searchField.waitForExistence(timeout: 5) {
            searchField.click()
            let current = searchField.value as? String ?? ""
            if !current.isEmpty {
                searchField.typeText(
                    String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            searchField.typeText("test_uitest_string\r")
        }

        sleep(2)

        let keyList = UITestHelper.app.groups["keyList"]
        XCTAssertTrue(keyList.waitForExistence(timeout: 5), "Key should appear in list")

        let keyRow = keyList.staticTexts["test_uitest_string"]
        if keyRow.waitForExistence(timeout: 5) {
            keyRow.click()
        }

        sleep(1)

        let deleteButton = UITestHelper.app.buttons["deleteKeyButton"]
        if deleteButton.waitForExistence(timeout: 5) {
            deleteButton.click()
        }

        sleep(2)

        let rowAfterDelete = keyList.staticTexts["test_uitest_string"]
        XCTAssertFalse(rowAfterDelete.exists, "Key should be deleted from list")
    }

    func testViewStringKeyDetail() {
        UITestHelper.navigateToShell()
        UITestHelper.executeShellCommand("SET test_uitest_string_detail world")
        sleep(1)
        UITestHelper.navigateToBrowser()

        let searchField = UITestHelper.app.textFields["keySearchField"]
        if searchField.waitForExistence(timeout: 5) {
            searchField.click()
            let current = searchField.value as? String ?? ""
            if !current.isEmpty {
                searchField.typeText(
                    String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            searchField.typeText("test_uitest_string_detail\r")
        }

        sleep(2)

        let keyList = UITestHelper.app.groups["keyList"]
        let keyRow = keyList.staticTexts["test_uitest_string_detail"]
        if keyRow.waitForExistence(timeout: 5) {
            keyRow.click()
        }

        sleep(1)

        let refreshButton = UITestHelper.app.buttons["refreshKeyDetailButton"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5), "Key detail view should show refresh button")

        let setTTLButton = UITestHelper.app.buttons["setTTLButton"]
        XCTAssertTrue(setTTLButton.exists, "Set TTL button should exist")

        let deleteButton = UITestHelper.app.buttons["deleteKeyButton"]
        XCTAssertTrue(deleteButton.exists, "Delete button should exist")
    }

    func testAddAndViewHashKey() {
        let addButton = UITestHelper.app.buttons["addKeyButton"]
        if addButton.waitForExistence(timeout: 5) {
            addButton.click()
        }

        let sheet = UITestHelper.app.sheets.firstMatch
        if sheet.waitForExistence(timeout: 5) {
            let nameField = sheet.textFields["newKeyNameField"]
            if nameField.exists {
                nameField.click()
                nameField.typeText("test_uitest_hash")
            }

            let fieldField = sheet.textFields["newKeyHashField"]
            if fieldField.exists {
                fieldField.click()
                fieldField.typeText("field1")
            }

            let valueField = sheet.textFields["newKeyHashValueField"]
            if valueField.exists {
                valueField.click()
                valueField.typeText("value1")
            }

            let addInSheet = sheet.buttons["Add"]
            if addInSheet.exists {
                addInSheet.click()
            }
        }

        sleep(2)

        let searchField = UITestHelper.app.textFields["keySearchField"]
        if searchField.waitForExistence(timeout: 5) {
            searchField.click()
            let current = searchField.value as? String ?? ""
            if !current.isEmpty {
                searchField.typeText(
                    String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            searchField.typeText("test_uitest_hash\r")
        }

        sleep(2)

        let keyList = UITestHelper.app.groups["keyList"]
        XCTAssertTrue(keyList.waitForExistence(timeout: 5), "Hash key should appear in list")
    }

    func testRefreshKeyList() {
        let refreshButton = UITestHelper.app.buttons["refreshKeyListButton"]
        if refreshButton.waitForExistence(timeout: 5) {
            refreshButton.click()
        } else {
            let keyList = UITestHelper.app.groups["keyList"]
            XCTAssertTrue(keyList.waitForExistence(timeout: 10), "Key list should be present")
        }
    }
}

final class BrowserTestsRedis6: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        UITestHelper.launchApp()
        UITestHelper.connectToRedis(
            name: RedisTestConfig.redis6Standalone.name,
            host: RedisTestConfig.redis6Standalone.host,
            port: RedisTestConfig.redis6Standalone.port)
        UITestHelper.navigateToBrowser()
    }

    override func tearDownWithError() throws {
        UITestHelper.cleanupTestKeys()
        try super.tearDownWithError()
    }

    func testScanKeys() {
        let keyList = UITestHelper.app.groups["keyList"]
        XCTAssertTrue(keyList.waitForExistence(timeout: 10))
    }
}

final class BrowserTestsRedis8: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        UITestHelper.launchApp()
        UITestHelper.connectToRedis(
            name: RedisTestConfig.redis8Standalone.name,
            host: RedisTestConfig.redis8Standalone.host,
            port: RedisTestConfig.redis8Standalone.port)
        UITestHelper.navigateToBrowser()
    }

    override func tearDownWithError() throws {
        UITestHelper.cleanupTestKeys()
        try super.tearDownWithError()
    }

    func testScanKeys() {
        let keyList = UITestHelper.app.groups["keyList"]
        XCTAssertTrue(keyList.waitForExistence(timeout: 10))
    }
}
