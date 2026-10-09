import XCTest

@MainActor
final class ClosetItemCareInstructionsUITests: XCTestCase {
    private let timeout: TimeInterval = ProcessInfo.processInfo.environment["CI"] == nil ? 20 : 60

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testCareInstructionsCanBeSavedAndClearedFromItemDetail() throws {
        let app = launchCloset()
        let itemName = "Care Notes UI \(Int(Date().timeIntervalSince1970))"
        addManualItem(named: itemName, in: app)
        openItem(named: itemName, in: app)
        let instructions = "Cold hand wash; lay flat to dry."
        saveCareInstructions(instructions, in: app)
        let savedNotes = careRow(with: instructions, in: app)
        XCTAssertTrue(savedNotes.waitForExistence(timeout: timeout))
        clearCareInstructions(instructions, in: app)
        XCTAssertTrue(careRow(with: instructions, in: app).waitForNonExistence(timeout: timeout))
    }

    private func launchCloset() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-astra-mock-backend",
            "-astra-skip-onboarding",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.chromeTabBar.waitForExistence(timeout: timeout))
        app.tapChromeTab("Closet", timeout: timeout)
        return app
    }

    private func addManualItem(named itemName: String, in app: XCUIApplication) {
        app.buttons["closet.header.addManually"].tap()
        let formHeader = app.descendants(matching: .any)["closet.form.header"]
        XCTAssertTrue(formHeader.waitForExistence(timeout: timeout))
        app.descendants(matching: .any)["closet.form.category.top"].tap()

        let nameField = app.descendants(matching: .any)["closet.form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText(itemName + "\n")
        let submitButton = app.descendants(matching: .any)["closet.form.submit"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: timeout))
        submitButton.tap()
        XCTAssertTrue(formHeader.waitForNonExistence(timeout: timeout))
    }

    private func openItem(named itemName: String, in app: XCUIApplication) {
        let topsTile = app.descendants(matching: .any)["closet.category.top"]
        XCTAssertTrue(topsTile.waitForExistence(timeout: timeout))
        topsTile.tap()
        let itemTile = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "closet.grid.item.",
                itemName
            )
        ).firstMatch
        XCTAssertTrue(itemTile.waitForExistence(timeout: timeout))
        itemTile.tap()
        XCTAssertTrue(app.staticTexts[itemName].firstMatch.waitForExistence(timeout: timeout))
    }

    private func saveCareInstructions(_ instructions: String, in app: XCUIApplication) {
        let formHeader = app.descendants(matching: .any)["closet.form.header"]
        let editButton = app.buttons["Edit"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: timeout))
        editButton.tap()
        XCTAssertTrue(formHeader.waitForExistence(timeout: timeout))
        let careField = app.descendants(matching: .any)["closet.form.careInstructions"]
        if !careField.exists {
            app.buttons["closet.form.moreDetails"].tap()
        }
        XCTAssertTrue(careField.waitForExistence(timeout: timeout))
        careField.tap()
        careField.typeText(instructions)
        let submitButton = app.descendants(matching: .any)["closet.form.submit"]
        submitButton.scrollIntoView(in: app)
        submitButton.tap()
        XCTAssertTrue(formHeader.waitForNonExistence(timeout: timeout))
    }

    private func clearCareInstructions(_ expected: String, in app: XCUIApplication) {
        let formHeader = app.descendants(matching: .any)["closet.form.header"]
        app.buttons["Edit"].firstMatch.tap()
        XCTAssertTrue(formHeader.waitForExistence(timeout: timeout))
        let savedCareField = app.descendants(matching: .any)["closet.form.careInstructions"]
        XCTAssertTrue(savedCareField.waitForExistence(timeout: timeout))
        XCTAssertEqual(savedCareField.value as? String, expected)
        let clearButton = app.buttons["closet.form.careInstructions.clear"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: timeout))
        clearButton.tap()
        XCTAssertTrue(clearButton.waitForNonExistence(timeout: timeout))
        let submitButton = app.descendants(matching: .any)["closet.form.submit"]
        submitButton.scrollIntoView(in: app)
        submitButton.tap()
        XCTAssertTrue(formHeader.waitForNonExistence(timeout: timeout))
    }

    private func careRow(with value: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND value == %@", "Care instructions", value)
        ).firstMatch
    }
}
