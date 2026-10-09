// P7-DS-01 draft: accessibility XXXL layout audit for five high-use screens.
// Uses the existing mock backend and the production More-tab helper.

import XCTest

@MainActor
final class DynamicTypeCriticalScreensUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private let timeout: TimeInterval = ProcessInfo.processInfo.environment["CI"] == nil ? 20 : 60
    private let maxAccessibilityCategory = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testDarkAccessibilityXXXLOnFiveCriticalScreens() throws {
        try audit(theme: "dark")
    }

    func testLightAccessibilityXXXLOnFiveCriticalScreens() throws {
        try audit(theme: "light")
    }

    private func audit(theme: String) throws {
        launchMain(theme: theme)
        auditHome(theme: theme)
        auditClosetAndOutfitDetail(theme: theme)
        auditPopulatedKyraConversation(theme: theme)
        auditPaywall(theme: theme)
    }

    private func launchMain(theme: String) {
        app.launchArguments = [
            "-UITestMode", "1",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", maxAccessibilityCategory,
            "-astra-reset-state",
            "-astra-mock-backend",
            "-astra-skip-onboarding",
            "-astra-theme", theme
        ]
        app.launch()
        let accountAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .alerts.matching(NSPredicate(format: "label CONTAINS %@", "Apple Account Verification"))
            .firstMatch
        if accountAlert.exists, accountAlert.buttons["Not Now"].exists {
            accountAlert.buttons["Not Now"].tap()
        }
        require(app.chromeTabBar, "Main tab bar")
    }

    private func auditHome(theme: String) {
        let primaryText = anyElement("home.todayLine")
        let wearAction = anyElement("home.wearThis")
        require(primaryText, "Home's populated outfit heading")
        require(wearAction, "Home's Wear This action")
        assertNoOverlap(primaryText, wearAction, "Home heading and Wear This")
        capture("P7-DS-01-\(theme)-AX5-home")

        wearAction.scrollIntoView(in: app, maxSwipes: 14)
        assertReachable(wearAction, "Home Wear This", avoidTabBar: true)
        capture("P7-DS-01-\(theme)-AX5-home-wear-action")
    }

    private func auditClosetAndOutfitDetail(theme: String) {
        app.tapChromeTab("Closet", timeout: timeout)
        let closetTitle = app.staticTexts["My Closet"].firstMatch
        let scanAction = anyElement("closet.header.scan")
        require(closetTitle, "Closet heading")
        require(scanAction, "Closet scan action")
        assertNoOverlap(closetTitle, scanAction, "Closet heading and Scan")
        capture("P7-DS-01-\(theme)-AX5-closet")

        scanAction.scrollIntoView(in: app, maxSwipes: 14)
        assertReachable(scanAction, "Closet Scan", avoidTabBar: true)

        // The shared helper scrolls in both directions and handles iOS's
        // system More list when Closet is overflowed at this size/device.
        let openLook = anyElement("closet.looks.open")
        openLook.scrollIntoView(in: app, maxSwipes: 14)
        require(openLook, "Saved outfit action in Closet's Looks carousel")
        XCTAssertTrue(openLook.isHittable, "Saved outfit action should be reachable at AX5")
        capture("P7-DS-01-\(theme)-AX5-closet-outfit-action")
        openLook.tap()

        let outfitTitle = app.staticTexts.matching(
            NSPredicate(
                format: "label IN %@",
                ["Client Meeting, Elevated Casual", "Denim & Oxford", "Dinner Out"]
            )
        ).firstMatch
        let markWorn = anyElement("outfitDetail.action.markWorn")
        require(outfitTitle, "Mock outfit title in detail")
        require(markWorn, "Outfit detail Mark Worn action")
        assertNoOverlap(outfitTitle, markWorn, "Outfit title and Mark Worn")
        capture("P7-DS-01-\(theme)-AX5-outfit-detail")

        markWorn.scrollIntoView(in: app, maxSwipes: 14)
        assertReachable(markWorn, "Outfit detail Mark Worn", avoidTabBar: true)
        capture("P7-DS-01-\(theme)-AX5-outfit-actions")
        app.navigationBars.buttons.firstMatch.tap()
        require(closetTitle, "Closet after returning from outfit detail")
    }

    private func auditPopulatedKyraConversation(theme: String) {
        app.tapChromeTab("Home", timeout: timeout)
        let askKyra = anyElement("kyra.ask")
        require(askKyra, "Home Ask Kyra action")
        askKyra.tap()

        let prompt = app.buttons["What should I wear tonight?"]
        require(prompt, "Kyra's first suggested prompt")
        prompt.scrollIntoView(in: app, maxSwipes: 14)
        XCTAssertTrue(prompt.isHittable, "Suggested prompt should be reachable at AX5")
        prompt.tap()

        let assistantReply = app.descendants(matching: .any)
            .matching(identifier: "kyra.message.assistant")
            .firstMatch
        let composer = anyElement("kyra.composer.field")
        require(assistantReply, "Populated mock Kyra response")
        require(composer, "Kyra composer")
        assertNoOverlap(assistantReply, composer, "Kyra response and composer")
        composer.scrollIntoView(in: app, maxSwipes: 14)
        XCTAssertTrue(composer.isHittable, "Kyra composer should remain reachable at AX5")
        capture("P7-DS-01-\(theme)-AX5-kyra-reply")
        anyElement("kyra.close").tap()
    }

    private func auditPaywall(theme: String) {
        app.terminate()
        app.launchArguments = [
            "-UITestMode", "1",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", maxAccessibilityCategory,
            "-astra-reset-state",
            "-astra-mock-backend",
            "-astra-skip-onboarding",
            "-astra-theme", theme,
            "-astra-audit-paywall", "studioQuota"
        ]
        app.launch()

        let hero = anyElement("paywall.hero")
        let title = app.staticTexts["Astra Style Premium"].firstMatch
        let subhead = app.staticTexts["One visual estimate on us. Upgrade for more."].firstMatch
        let restore = anyElement("paywall.restore")
        let monthly = anyElement("paywall.plan.com.astrastyle.app.premium.monthly")
        let annual = anyElement("paywall.plan.com.astrastyle.app.premium.annual")
        require(hero, "Paywall hero")
        require(title, "Paywall primary heading")
        require(subhead, "Paywall quota explanation")
        require(monthly, "Mock monthly Premium plan")
        require(annual, "Mock annual Premium plan")
        require(restore, "Paywall Restore Purchases action")
        XCTAssertTrue(monthly.label.contains("TEST ONLY"), "Monthly fixture must be clearly non-billable")
        XCTAssertTrue(annual.label.contains("TEST ONLY"), "Annual fixture must be clearly non-billable")
        XCTAssertTrue(hero.frame.contains(title.frame), "Paywall title must stay inside the hero at AX5")
        XCTAssertTrue(hero.frame.contains(subhead.frame), "Paywall quota explanation must stay inside the hero at AX5")
        assertNoOverlap(title, restore, "Paywall title and Restore Purchases")
        assertNoOverlap(subhead, restore, "Paywall quota explanation and Restore Purchases")
        capture("P7-DS-01-\(theme)-AX5-paywall")

        monthly.scrollIntoView(in: app, maxSwipes: 14)
        assertReachable(monthly, "Paywall monthly fixture plan", avoidTabBar: false)
        capture("P7-DS-01-\(theme)-AX5-paywall-monthly")

        annual.scrollIntoView(in: app, maxSwipes: 14)
        assertReachable(annual, "Paywall annual fixture plan", avoidTabBar: false)
        capture("P7-DS-01-\(theme)-AX5-paywall-annual")

        restore.scrollIntoView(in: app, maxSwipes: 14)
        assertReachable(restore, "Paywall Restore Purchases", avoidTabBar: false)
        capture("P7-DS-01-\(theme)-AX5-paywall-restore")
    }

    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func require(
        _ element: XCUIElement,
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Never appeared: \(description)", file: file, line: line)
    }

    private func assertNoOverlap(
        _ primaryText: XCUIElement,
        _ control: XCUIElement,
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        require(primaryText, "\(description) primary text", file: file, line: line)
        require(control, "\(description) control", file: file, line: line)
        XCTAssertFalse(
            primaryText.frame.intersects(control.frame),
            "\(description) overlaps at Accessibility XXXL: text=\(primaryText.frame), control=\(control.frame)",
            file: file,
            line: line
        )
    }

    private func assertReachable(
        _ control: XCUIElement,
        _ description: String,
        avoidTabBar: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        require(control, description, file: file, line: line)
        XCTAssertTrue(control.isHittable, "\(description) is not reachable after scrolling at AX5", file: file, line: line)
        if avoidTabBar {
            XCTAssertFalse(
                control.frame.intersects(app.chromeTabBar.frame),
                "\(description) is obscured by the system tab bar at AX5",
                file: file,
                line: line
            )
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
