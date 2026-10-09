import XCTest

@MainActor
final class StyleQuizRefinementUITests: XCTestCase {
    private let timeout: TimeInterval = 30
    private lazy var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testFullProfileRefinementAndDNAOnlyRetry() {
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-astra-reset-state",
            "-astra-mock-backend",
            "-astra-skip-onboarding",
            "-astra-test-taste-refinement-dna-fail-once"
        ]
        app.launch()

        app.tapChromeTab("Profile", timeout: timeout)

        let openRefinement = app.buttons["profile.tasteRefinementRow"]
        XCTAssertTrue(openRefinement.waitForExistence(timeout: timeout))
        openRefinement.tap()
        XCTAssertTrue(app.navigationBars["Taste refinement"].waitForExistence(timeout: timeout))

        let progress = app.staticTexts["onboarding.quiz.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: timeout))
        let total = Int(progress.label.components(separatedBy: " of ").last ?? "")
        XCTAssertNotNil(total)
        XCTAssertGreaterThanOrEqual(total ?? 0, 12)

        let noPreference = app.buttons["onboarding.quiz.noPreference"]
        let save = app.buttons["profile.tasteRefinement.save"]
        var answerCount = 0
        for _ in 0..<12 {
            XCTAssertTrue(noPreference.waitForExistence(timeout: timeout))
            noPreference.tap()
            answerCount += 1
        }
        XCTAssertFalse(save.isEnabled, "A full refinement must not save after only twelve answers.")

        while answerCount < (total ?? 20) {
            XCTAssertTrue(noPreference.waitForExistence(timeout: timeout))
            noPreference.tap()
            answerCount += 1
        }
        XCTAssertTrue(save.isEnabled, "Every pair should enable a complete answer set.")
        XCTAssertEqual(answerCount, total)
        save.tap()

        let savedButDNADelayed = app.staticTexts[
            "Your answers are saved. Style DNA could not refresh."
        ]
        XCTAssertTrue(savedButDNADelayed.waitForExistence(timeout: timeout))
        let retry = app.buttons["Retry Style DNA"]
        XCTAssertTrue(retry.waitForExistence(timeout: timeout))
        retry.tap()
        XCTAssertTrue(app.staticTexts["Your taste profile is up to date."].waitForExistence(timeout: timeout))
    }
}
