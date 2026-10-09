import XCTest

/// Native paste-to-verdict acceptance with deterministic repositories.
/// Live extraction/provider acceptance is a separate backend gate.
@MainActor
final class ProductLinkFlowUITests: XCTestCase {
    private let app = XCUIApplication()
    private let timeout: TimeInterval = 30

    override func setUp() async throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Apple Account Verification") { alert in
            guard alert.label.contains("Apple Account Verification") else { return false }
            let dismiss = alert.buttons["Not Now"]
            guard dismiss.exists else { return false }
            dismiss.tap()
            return true
        }
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-astra-reset-state", "-astra-mock-backend", "-astra-skip-onboarding"
        ]
        app.launch()
        XCTAssertTrue(element("main.tabBar").waitForExistence(timeout: timeout))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testPastedProductReachesVerdictAndCanBeSaved() {
        let options = element("home.moreOptions")
        options.scrollIntoView(in: app)
        XCTAssertTrue(options.waitForExistence(timeout: timeout))
        options.tap()
        let paste = element("home.pasteLink")
        XCTAssertTrue(paste.waitForExistence(timeout: timeout))
        paste.tap()

        let field = app.textFields["home.productLink.field"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        let submit = element("home.productLink.submit")
        XCTAssertFalse(submit.isEnabled, "Empty URLs must not submit")
        field.tap()
        field.typeText("not-a-product-url")
        XCTAssertFalse(submit.isEnabled, "Invalid URLs must not submit")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "not-a-product-url".count))
        field.typeText("https://example.com/products/navy-shirt")
        XCTAssertTrue(submit.isEnabled, "A valid product URL must enable evaluation")
        submit.tap()

        let verdict = element("productDecision.verdict")
        XCTAssertTrue(verdict.waitForExistence(timeout: timeout))
        XCTAssertEqual(verdict.label, "Worth considering")
        let reasoning = element("productDecision.reasoning")
        reasoning.scrollIntoView(in: app)
        XCTAssertFalse(reasoning.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let unlocks = element("productDecision.unlocks")
        XCTAssertTrue(unlocks.exists)
        XCTAssertTrue(unlocks.label.contains("9"), "The result must show the mock's computed unlock count")
        let save = element("productDecision.wishlist")
        save.scrollIntoView(in: app)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: timeout))
        let verification = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .alerts["Apple Account Verification"]
        if verification.exists {
            let dismiss = verification.buttons["Not Now"]
            XCTAssertTrue(dismiss.exists)
            dismiss.tap()
            XCTAssertFalse(verification.exists)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Pasted-Product-Saved-Verdict"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
