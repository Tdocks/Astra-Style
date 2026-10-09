import XCTest

@MainActor
final class ShopTheLookUITests: XCTestCase {
    private let app = XCUIApplication()
    private let timeout: TimeInterval = 20

    func testOwnedAndCandidateBackedMissingItemsShowFactsAndProductRoute() {
        launchMain(includingCandidate: true)
        openSavedOutfit()

        let ownedSection = anyElement("shopTheLook.owned")
        let missingSection = anyElement("shopTheLook.missing")
        XCTAssertTrue(ownedSection.waitForExistence(timeout: timeout))
        XCTAssertTrue(missingSection.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Already in your wardrobe"].exists)
        XCTAssertTrue(app.staticTexts["Pieces to complete the look"].exists)
        XCTAssertTrue(app.staticTexts["Owned"].exists)
        missingSection.scrollIntoView(in: app, maxSwipes: 12)
        XCTAssertTrue(app.staticTexts["Test Wool Overshirt"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Outfit Goods"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "$180")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Listed sizes: XS, M, XL"].exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "may earn a commission")
        ).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Sponsored"].exists)

        let candidateDisclosure = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Affiliate link: Astra Style may earn a commission")
        ).firstMatch
        XCTAssertTrue(candidateDisclosure.exists, "Affiliate disclosure must appear on the product card itself")
        XCTAssertFalse(anyElement("shopTheLook.missing.empty").exists)

        // The enclosing outfit/card containers have their own identifiers;
        // target the unique visible action label instead of depending on a
        // nested identifier surviving SwiftUI's accessibility grouping.
        let reviewProduct = app.buttons["Review product"]
        reviewProduct.scrollIntoView(in: app, maxSwipes: 12)
        reviewProduct.tap()
        XCTAssertTrue(app.navigationBars["Should you buy this?"].waitForExistence(timeout: timeout))
    }

    func testClosetOnlySavedLookExplainsThatNoProductsAreAttached() {
        launchMain(includingCandidate: false)
        openSavedOutfit()

        XCTAssertTrue(anyElement("shopTheLook.owned").waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Owned"].exists)
        let emptyState = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "No researched products are attached")
        ).firstMatch
        XCTAssertTrue(emptyState.waitForExistence(timeout: timeout))
        emptyState.scrollIntoView(in: app, maxSwipes: 12)
        XCTAssertFalse(app.staticTexts["Test Wool Overshirt"].exists)
        XCTAssertTrue(app.buttons["Browse Shop catalog"].exists)
    }

    private func launchMain(includingCandidate: Bool) {
        app.launchArguments = [
            "-astra-reset-state",
            "-astra-mock-backend",
            "-astra-skip-onboarding"
        ]
        if includingCandidate {
            app.launchArguments.append("-astra-test-shop-the-look-candidate")
        }
        app.launch()
        XCTAssertTrue(app.chromeTabBar.waitForExistence(timeout: timeout))
    }

    private func openSavedOutfit() {
        app.tapChromeTab("Closet", timeout: timeout)
        let openLook = app.buttons["closet.looks.open"].firstMatch
        openLook.scrollIntoView(in: app, maxSwipes: 12)
        XCTAssertTrue(openLook.waitForExistence(timeout: timeout))
        openLook.tap()

        let expectedOutfitName = app.staticTexts[
            app.launchArguments.contains("-astra-test-shop-the-look-candidate")
                ? "Shop the Look UI Fixture"
                : "Client Meeting, Elevated Casual"
        ]
        XCTAssertTrue(expectedOutfitName.waitForExistence(timeout: timeout))
        let shopThisLook = app.buttons["outfitDetail.action.shopThisLook"]
        shopThisLook.scrollIntoView(in: app, maxSwipes: 12)
        XCTAssertTrue(shopThisLook.waitForExistence(timeout: timeout))
        shopThisLook.tap()
        XCTAssertTrue(app.navigationBars["Shop this look"].waitForExistence(timeout: timeout))
    }

    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
