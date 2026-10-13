import XCTest

/// Simulator acceptance with deliberate failures in real view-model/repository
/// boundaries. These fixtures do not claim hosted provider or Apple sandbox delivery.
@MainActor
final class RemainingJourneyAcceptanceUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws { continueAfterFailure = false }

    private func launch(_ flags: [String] = []) {
        app.launchArguments = ["-astra-reset-state", "-astra-mock-backend", "-astra-skip-onboarding",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + flags
        app.launch()
        XCTAssertTrue(app.chromeTabBar.waitForExistence(timeout: 30))
    }

    func testScannerRecoversInterruptedAnalysisAndSave() throws {
        launch(["-astra-test-scanner-fail-once"])
        app.tapChromeTab("Closet")
        app.buttons["closet.header.scan"].tap()
        app.buttons["Scan One Piece"].tap()
        let choose = app.descendants(matching: .any)["scanner.capture.import"]
        XCTAssertTrue(choose.waitForExistence(timeout: 20))
        choose.tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 20), "Seed one representative garment photo before running")
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["scanner.capture.draft"].waitForExistence(timeout: 20))
        app.buttons["Continue"].tap()
        let retry = app.buttons["scanner.review.retryPending"]
        retry.scrollIntoView(in: app)
        let state = XCTAttachment(screenshot: app.screenshot())
        state.name = "Scanner-interrupted-analysis"
        state.lifetime = .keepAlways
        add(state)
        XCTAssertTrue(retry.waitForExistence(timeout: 20), "Interrupted analysis must offer recovery")
        retry.tap()
        let name = app.textFields["scanner.review.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 20))
        name.tap()
        let old = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "Recovery garment\n")
        let save = app.buttons["scanner.review.save"]
        save.scrollIntoView(in: app)
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any)["scanner.review.error"].waitForExistence(timeout: 20))
        XCTAssertTrue(save.isEnabled, "Failed save must remain retryable")
        save.tap()
        let done = app.buttons["scanner.review.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 20))
        done.tap()
        let closet = app.buttons["closet.header.scan"]
        XCTAssertTrue(closet.waitForExistence(timeout: 20))
        XCTAssertTrue(closet.isHittable, "Done must close the scanner back to Closet")
    }

    func testStudioGenerationRecoversProviderFailure() throws {
        launch(["-astra-test-studio-fail-once"])
        let entry = app.buttons["home.style.inspiration"]
        entry.scrollIntoView(in: app)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Inspiration"].waitForExistence(timeout: 20))
        let generate = app.buttons["home.inspiration.generate"]
        app.waitForInspirationReady(generateButton: generate, timeout: 20)
        generate.scrollIntoView(in: app)
        generate.tap()
        let retry = app.buttons["Check again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 30))
        retry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.inspiration.image"].waitForExistence(timeout: 30))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
    }

    func testPaidTransactionSyncRecoveryIsReachable() throws {
        launch(["-astra-audit-paywall", "settingsUpgrade", "-astra-test-purchase-sync-fail-once"])
        let plan = app.buttons["paywall.plan.com.astrastyle.app.premium.monthly"]
        XCTAssertTrue(plan.waitForExistence(timeout: 20))
        plan.tap()
        XCTAssertTrue(app.descendants(matching: .any)["paywall.error"].waitForExistence(timeout: 20))
        XCTAssertFalse(plan.isEnabled, "A paid but unsynced purchase must not start another purchase")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        let retry = app.buttons["paywall.retry"]
        retry.scrollIntoView(in: app)
        retry.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                   object: app.descendants(matching: .any)["paywall.hero"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 20), .completed)
    }

}
