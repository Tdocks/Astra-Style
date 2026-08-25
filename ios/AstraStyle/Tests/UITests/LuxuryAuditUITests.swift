//
//  LuxuryAuditUITests.swift
//  AstraStyleUITests
//
//  Screenshot-backed audit of the product below its tab roots. The existing
//  ScreenQAUITests proves every root renders; this suite opens the decisions,
//  consent gates, details, and trust surfaces that determine whether Astra
//  feels like a private stylist or a collection of tabs.
//

import XCTest

@MainActor
final class LuxuryAuditUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private let timeout: TimeInterval = ProcessInfo.processInfo.environment["CI"] == nil ? 20 : 60

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launchMain(extraArguments: [String] = []) {
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-astra-reset-state",
            "-astra-mock-backend",
            "-astra-skip-onboarding",
        ] + extraArguments
        app.launch()
        awaitElement(app.chromeTabBar, "Main tab bar")
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @discardableResult
    private func awaitElement(
        _ element: XCUIElement,
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let found = element.waitForExistence(timeout: timeout)
        if !found { XCTFail("Never appeared: \(description)", file: file, line: line) }
        return found
    }

    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testHomeDecisionAndVisualizeConsent() {
        launchMain()

        awaitElement(anyElement("home.look"), "Home populated look")
        capture("60-Home-Populated-Top")

        let wear = anyElement("home.wearThis")
        wear.scrollIntoView(in: app)
        capture("61-Home-Actions")
        wear.tap()
        XCTAssertTrue(
            app.buttons["Worn today"].waitForExistence(timeout: timeout)
                || wear.isEnabled == false,
            "Wear This did not settle into a completed state"
        )
        capture("62-Home-Worn")

        let visualize = anyElement("home.seeOnYou")
        visualize.scrollIntoView(in: app)
        visualize.tap()
        awaitElement(anyElement("studio.consent"), "Studio consent from today's look")
        capture("63-Studio-Consent")
        anyElement("studio.consent").tap()
        capture("64-Studio-Consent-Acknowledged")
        app.buttons["Close"].firstMatch.tap()
        awaitElement(anyElement("home.look"), "Home after closing Studio")
    }

    func testClosetDetailsFiltersAndScannerDoors() {
        launchMain()
        app.tapChromeTab("Closet")
        awaitElement(app.staticTexts["My Closet"].firstMatch, "Closet root")
        capture("65-Closet-Populated")

        let filters = anyElement("closet.header.filters")
        filters.tap()
        awaitElement(anyElement("closet.filter.done"), "Closet filters")
        capture("66-Closet-Filters")
        anyElement("closet.filter.done").tap()

        let firstItem = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "closet.grid.item.")
        ).firstMatch
        firstItem.scrollIntoView(in: app)
        firstItem.tap()
        awaitElement(app.navigationBars.firstMatch, "Closet item detail")
        capture("67-Closet-Item-Detail")
        app.navigationBars.buttons.firstMatch.tap()

        awaitElement(anyElement("closet.header.scan"), "Closet scan menu")
        anyElement("closet.header.scan").tap()
        app.buttons["Add Several at Once"].tap()
        awaitElement(anyElement("scanner.batch.choose"), "Batch scanner")
        capture("68-Scanner-Batch")
        app.buttons["Close"].firstMatch.tap()

        awaitElement(anyElement("closet.header.scan"), "Closet scan menu after batch")
        anyElement("closet.header.scan").tap()
        app.buttons["Scan One Piece"].tap()
        awaitElement(anyElement("scanner.capture.import"), "Single scanner")
        capture("69-Scanner-Single")
        anyElement("scanner.capture.close").tap()
    }

    func testDiscoverShopAndProductDecision() {
        launchMain()
        app.tapChromeTab("Discover")
        let mine = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "discover.mine.")
        ).firstMatch
        awaitElement(mine, "Discover owned-look rail")
        usleep(600_000)
        capture("70-Discover-Rails")

        let ownedLook = mine
        if ownedLook.exists && !ownedLook.identifier.hasSuffix(".empty") {
            ownedLook.tap()
            awaitElement(app.navigationBars.firstMatch, "Discover outfit detail")
            capture("71-Discover-Lookbook-Detail")
            app.navigationBars.buttons.firstMatch.tap()
        }

        app.tapChromeTab("Shop")
        awaitElement(anyElement("shop.catalog"), "Shop catalog")
        capture("72-Shop-Catalog")
        let product = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Italian Shearling Jacket")
        ).firstMatch
        awaitElement(product, "Shop product")
        product.tap()
        awaitElement(anyElement("productDecision.verdict"), "Product decision")
        capture("73-Product-Decision-Top")
        anyElement("productDecision.reasoning").scrollIntoView(in: app)
        capture("74-Product-Decision-Reasoning")
        anyElement("productDecision.wishlist").tap()
        capture("75-Product-Decision-Saved")
    }

    func testKyraProfileAndPrivacyTrustSurfaces() {
        launchMain()

        anyElement("kyra.ask").tap()
        awaitElement(anyElement("kyra.empty"), "New Kyra conversation")
        capture("76-Kyra-Empty")
        let firstPrompt = app.buttons["What should I wear tonight?"]
        awaitElement(firstPrompt, "First Kyra suggested prompt")
        firstPrompt.tap()
        awaitElement(
            app.descendants(matching: .any)["kyra.message.assistant"].firstMatch,
            "Kyra response"
        )
        capture("77-Kyra-Structured-Reply")
        anyElement("kyra.close").tap()

        app.tapChromeTab("Profile")
        awaitElement(anyElement("profile.about.version"), "Profile")
        capture("78-Profile-Top")
        let appearance = anyElement("profile.appearanceRow")
        appearance.scrollIntoView(in: app)
        appearance.tap()
        let deep = app.buttons["Deep"]
        awaitElement(deep, "Profile appearance editor")
        capture("79-Profile-Appearance-Editor")
        // Profile is under More, so two BackButtons exist (More and Back).
        // The inner Back returns to Profile; the More button would leave the tab.
        let back = app.navigationBars.buttons["Back"]
        if back.waitForExistence(timeout: 3) {
            back.tap()
        } else {
            app.navigationBars.buttons.firstMatch.tap()
        }
        awaitElement(anyElement("profile.about.version"), "Profile after appearance editor")

        let privacy = anyElement("profile.privacyAndDataRow")
        privacy.scrollIntoView(in: app)
        capture("80-Profile-Trust-Rows")
        privacy.tap()
        awaitElement(anyElement("privacyAndData.deleteAccountRow"), "Privacy and Data")
        capture("81-Privacy-And-Data")
        anyElement("privacyAndData.deleteAccountRow").tap()
        awaitElement(anyElement("accountDeletion.deleteButton"), "Account deletion confirmation")
        capture("82-Account-Deletion-Confirmation")
    }

    func testEveryPaywallContext() {
        let contexts = [
            "onboarding",
            "closetLimit",
            "outfitGenerationLimit",
            "dailyBrief",
            "pasteEvaluate",
            "studioQuota",
            "kyraDailyLimit",
            "settingsUpgrade",
        ]

        for (index, context) in contexts.enumerated() {
            launchMain(extraArguments: ["-astra-audit-paywall", context])
            awaitElement(anyElement("paywall.hero"), "Paywall context \(context)")
            capture(String(format: "%02d-Paywall-%@", 83 + index, context))
            app.terminate()
        }
    }
}
