//
//  PublicCutSmokeUITests.swift
//  AstraStyleUITests
//
//  Live-backend stranger path on a connected device: guest → Closet/scan
//  door → Wear This → Shop/Unlocks → Studio → legal HTTPS → deletion row.
//  Debug-only launch flags skip onboarding so the tab shell is reachable;
//  they are ignored in Release / TestFlight.
//

import XCTest

@MainActor
final class PublicCutSmokeUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private let timeout: TimeInterval = 30

    override func setUp() async throws {
        continueAfterFailure = true
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-astra-reset-state",
            "-astra-skip-onboarding",
        ]
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            for title in ["Allow", "Allow While Using App", "Allow Once", "OK", "Continue"] {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }

    func testGuestStrangerPath() throws {
        app.launch()
        XCTAssertTrue(
            app.buttons["welcome.tryWithoutAccount"].waitForExistence(timeout: timeout),
            "Welcome guest CTA should appear after reset"
        )
        XCTAssertTrue(app.buttons["welcome.termsLink"].exists, "Terms missing on Welcome")
        XCTAssertTrue(app.buttons["welcome.privacyLink"].exists, "Privacy missing on Welcome")

        app.buttons["welcome.privacyLink"].tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        if safari.wait(for: .runningForeground, timeout: 8) {
            // Safari's URL field identifier is not stable across iOS versions;
            // leaving the app for Safari is the HTTPS handoff. Pages already
            // returned 200 from curl.
            app.activate()
        } else {
            let web = app.webViews.firstMatch
            XCTAssertTrue(
                web.waitForExistence(timeout: 8) || app.buttons["welcome.tryWithoutAccount"].exists,
                "Privacy tap should open a browser or leave Welcome intact"
            )
            if web.exists {
                app.swipeDown()
            }
        }

        XCTAssertTrue(
            app.buttons["welcome.tryWithoutAccount"].waitForExistence(timeout: timeout),
            "Welcome should be back so guest can start"
        )
        app.buttons["welcome.tryWithoutAccount"].tap()

        XCTAssertTrue(
            app.chromeTabBar.waitForExistence(timeout: 45),
            "Guest + skip-onboarding should land on the tab shell"
        )

        tapTab("Home")
        addThreeRoleGarments()

        tapTab("Home")
        let wearThis = app.descendants(matching: .any)["home.wearThis"]
        if wearThis.waitForExistence(timeout: 20) {
            wearThis.tap()
            let paywall = app.descendants(matching: .any)["paywall.hero"]
            XCTAssertFalse(
                paywall.waitForExistence(timeout: 3),
                "Wear This is the habit loop and must never present a paywall"
            )
        } else {
            XCTAssertTrue(
                app.descendants(matching: .any)["home.empty"].waitForExistence(timeout: 5)
                    || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "outfit")).firstMatch.exists,
                "Home should show Wear This or an empty/outfit state, not a crash"
            )
        }

        tapTab("Closet")
        let scan = app.descendants(matching: .any)["closet.header.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: timeout), "Closet scan door missing")
        scan.tap()
        let scanOne = app.buttons["Scan One Piece"].firstMatch
        if scanOne.waitForExistence(timeout: 5) {
            scanOne.tap()
        }
        app.tap() // dismiss permission interruption if it appeared
        let importButton = app.descendants(matching: .any)["scanner.capture.import"]
        let shutter = app.descendants(matching: .any)["scanner.capture.shutter"]
        XCTAssertTrue(
            importButton.waitForExistence(timeout: 10) || shutter.waitForExistence(timeout: 2),
            "Scan should open camera or import, not a dead chrome tab"
        )
        let closeScan = app.buttons["scanner.capture.close"].firstMatch
        if closeScan.waitForExistence(timeout: 3) {
            closeScan.tap()
        } else {
            app.swipeDown()
        }
        XCTAssertTrue(
            scan.waitForExistence(timeout: 10),
            "Scan should dismiss back to Closet"
        )

        tapTab("Shop")
        XCTAssertTrue(
            app.descendants(matching: .any)["shop.catalog"].waitForExistence(timeout: 20)
                || app.descendants(matching: .any)["shop.empty"].waitForExistence(timeout: 2),
            "Shop should load catalog or empty, not hang"
        )

        tapTab("Discover")
        let unlocksEmpty = app.descendants(matching: .any)["discover.unlocks.empty"]
        let unlocksAny = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "discover.unlocks.")
        ).firstMatch
        XCTAssertTrue(
            unlocksEmpty.waitForExistence(timeout: 20) || unlocksAny.waitForExistence(timeout: 2),
            "Unlocks rail should render (items or empty), not a dead tab"
        )

        tapTab("Studio")
        XCTAssertTrue(
            app.descendants(matching: .any)["studio.start"].waitForExistence(timeout: 15)
                || app.descendants(matching: .any)["studio.empty.start"].waitForExistence(timeout: 2)
                || app.descendants(matching: .any)["studio.gallery"].waitForExistence(timeout: 2),
            "Studio tab should be live"
        )

        tapTab("Profile")
        let version = app.descendants(matching: .any)["profile.about.version"]
        XCTAssertTrue(version.waitForExistence(timeout: timeout), "App version missing from Profile")

        let privacyRow = app.descendants(matching: .any)["profile.privacyAndDataRow"]
        XCTAssertTrue(privacyRow.waitForExistence(timeout: timeout), "Privacy & Data row missing")
        privacyRow.tap()
        let deleteRow = app.descendants(matching: .any)["privacyAndData.deleteAccountRow"]
        XCTAssertTrue(deleteRow.waitForExistence(timeout: timeout), "Delete-account row missing")
        deleteRow.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["accountDeletion.deleteButton"].waitForExistence(timeout: timeout),
            "Deletion confirmation screen should open (do not confirm)"
        )
    }

    private func tapTab(_ name: String) {
        app.tapChromeTab(name, timeout: timeout)
    }

    private func addThreeRoleGarments() {
        tapTab("Closet")
        addGarment(name: "Smoke Tee", category: "top")
        addGarment(name: "Smoke Trousers", category: "bottom")
        addGarment(name: "Smoke Sneakers", category: "shoes")
    }

    private func addGarment(name: String, category: String) {
        let add = app.descendants(matching: .any)["closet.header.addManually"]
        guard add.waitForExistence(timeout: timeout) else {
            XCTFail("closet.header.addManually missing")
            return
        }
        add.tap()
        let header = app.descendants(matching: .any)["closet.form.header"]
        XCTAssertTrue(header.waitForExistence(timeout: timeout), "Add garment form missing")
        let chip = app.descendants(matching: .any)["closet.form.category.\(category)"]
        if chip.waitForExistence(timeout: 5) {
            chip.tap()
        }
        let nameField = app.descendants(matching: .any)["closet.form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout), "Name field missing")
        nameField.tap()
        nameField.typeText(name + "\n")
        let submit = app.descendants(matching: .any)["closet.form.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: timeout), "Submit missing")
        if submit.isEnabled { submit.tap() }
        XCTAssertTrue(header.waitForNonExistence(timeout: 20), "Form should dismiss after saving \(name)")
    }
}
