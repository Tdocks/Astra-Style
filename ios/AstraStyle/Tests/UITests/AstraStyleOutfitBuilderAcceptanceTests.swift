import XCTest

@MainActor
final class OutfitBuilderAcceptanceUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private let timeout: TimeInterval = ProcessInfo.processInfo.environment["CI"] == nil ? 20 : 60

    override func setUp() async throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Apple Account Verification") { alert in
            guard alert.label.contains("Apple Account Verification") else { return false }
            let notNow = alert.buttons["Not Now"]
            guard notNow.exists else { return false }
            notNow.tap()
            return true
        }
        app.launchArguments += ["-UITestMode", "1", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    private func awaitElement(_ element: XCUIElement, _ description: String) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Never appeared: \(description)")
    }

    private func launchMockMain() {
        app.launchArguments += ["-astra-reset-state", "-astra-mock-backend", "-astra-skip-onboarding"]
        app.launch()
        awaitElement(app.chromeTabBar, "Main tab bar under mock backend")
    }

    /// Exercises durable Kyra completion through the actual builder controls.
    /// The seeded mock outfit is owner-scoped and has real closet item rows.
    func testAskKyraCompletesBuilderWithoutReplacingLockedPiece() throws {
        launchMockMain()
        let closetDoor = app.buttons["home.style.fromCloset"]
        awaitElement(closetDoor, "Closet outfit entry point")
        closetDoor.tap()

        let generate = app.buttons["outfitBuilder.generateRecommendations"]
        awaitElement(generate, "Outfit builder")
        generate.tap()
        let firstRecommendation = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "outfitBuilder.chooseRecommendation.")
        ).firstMatch
        awaitElement(firstRecommendation, "Generated owned outfit recommendation")
        firstRecommendation.tap()

        let topSlot = app.buttons["outfitBuilder.slot.top"]
        awaitElement(topSlot, "Top slot")
        topSlot.press(forDuration: 1.1)
        XCTAssertTrue(topSlot.label.localizedCaseInsensitiveContains("locked"))

        let askKyra = app.buttons["outfitBuilder.askKyra"]
        askKyra.scrollIntoView(in: app)
        awaitElement(askKyra, "Ask Kyra to finish")
        askKyra.tap()
        let reason = app.staticTexts["outfitBuilder.kyraReason"]
        awaitElement(reason, "Kyra completion reason")
        XCTAssertFalse(reason.label.isEmpty)
        XCTAssertTrue(topSlot.label.localizedCaseInsensitiveContains("locked"))
    }

    /// Saves then changes the same builder-backed outfit through the public UI.
    /// The “Save changes” state and retained detail actions demonstrate the edit
    /// route; repository/RPC tests assert the identity and concurrency contract.
    func testSavedBuilderCanEditAndSaveChanges() throws {
        launchMockMain()
        let closetDoor = app.buttons["home.style.fromCloset"]
        awaitElement(closetDoor, "Closet outfit entry point")
        closetDoor.tap()
        let generate = app.buttons["outfitBuilder.generateRecommendations"]
        awaitElement(generate, "Outfit builder")
        generate.tap()
        let firstRecommendation = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "outfitBuilder.chooseRecommendation.")
        ).firstMatch
        awaitElement(firstRecommendation, "Generated recommendation")
        firstRecommendation.tap()
        let save = app.buttons["outfitBuilder.save"]
        save.scrollIntoView(in: app)
        awaitElement(save, "Save outfit")
        save.tap()
        XCTAssertTrue(app.buttons["outfitBuilder.visualize"].waitForExistence(timeout: timeout))
        XCTAssertTrue(save.label.localizedCaseInsensitiveContains("Save changes"))

        let bottomSlot = app.buttons["outfitBuilder.slot.bottom"]
        bottomSlot.scrollIntoView(in: app)
        awaitElement(bottomSlot, "Editable bottom slot")
        bottomSlot.tap()
        let pickerItem = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "outfitBuilder.picker.item.")
        ).firstMatch
        awaitElement(pickerItem, "Owned replacement garment")
        pickerItem.tap()
        save.scrollIntoView(in: app)
        save.tap()
        XCTAssertTrue(app.buttons["outfitBuilder.visualize"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["outfitBuilder.refineWithKyra"].exists)
    }
}
