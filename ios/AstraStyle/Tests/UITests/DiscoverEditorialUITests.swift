import XCTest

@MainActor
final class DiscoverEditorialUITests: XCTestCase {
    private let timeout: TimeInterval = 30
    private lazy var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launchMockMain() {
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-astra-reset-state",
            "-astra-mock-backend",
            "-astra-skip-onboarding"
        ]
        app.launch()
        XCTAssertTrue(app.chromeTabBar.waitForExistence(timeout: 45), "Mock app should open the tab shell")
    }

    func testEveryEditorialCategoryOpensItsConfiguredArticle() {
        launchMockMain()
        app.tapChromeTab("Discover", timeout: timeout)

        openGuide(cardID: "discover.editorial.style.one-anchor-at-a-time", articleID: "discover.guide.one-anchor-at-a-time")
        openGuide(cardID: "discover.editorial.seasonal.warm-weather-breathing-room", articleID: "discover.guide.warm-weather-breathing-room")
        openGuide(cardID: "discover.editorial.fit.fit-through-the-shoulder", articleID: "discover.guide.fit-through-the-shoulder")
        openGuide(
            cardID: "discover.editorial.brand.drakes-field-notes",
            articleID: "discover.guide.drakes-field-notes",
            verifiesBrandAttribution: true
        )
    }

    private func openGuide(cardID: String, articleID: String, verifiesBrandAttribution: Bool = false) {
        let card = app.descendants(matching: .any)[cardID]
        for _ in 0..<8 where !card.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(card.waitForExistence(timeout: timeout), "Missing editorial card: \(cardID)")
        card.tap()
        let article = app.descendants(matching: .any)[articleID]
        XCTAssertTrue(article.waitForExistence(timeout: timeout), "Guide route did not load configured article: \(articleID)")
        if verifiesBrandAttribution {
            XCTAssertTrue(app.descendants(matching: .any)["discover.guide.commercial-label"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["discover.guide.sources"].exists)
        }
        let articleNavigation = app.navigationBars[article.label]
        XCTAssertTrue(articleNavigation.waitForExistence(timeout: timeout))
        let back = articleNavigation.buttons["Discover"]
        XCTAssertTrue(back.waitForExistence(timeout: timeout), "Article must return to Discover, not the outer More list")
        back.tap()

    }
}
