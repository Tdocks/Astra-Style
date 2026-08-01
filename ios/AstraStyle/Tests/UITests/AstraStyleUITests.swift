//
//  AstraStyleUITests.swift
//  AstraStyleUITests
//
//  Spec §22 "UI tests" — XCUITest (not Swift Testing; UI automation still
//  needs `XCTest`/`XCUIApplication` even in an otherwise Swift-Testing
//  codebase, per the build instructions).
//
//  Flows that are not yet built remain `XCTSkip` placeholders so the gap
//  shows up in Xcode/CI's test report rather than being silently missing.
//  Written bodies (today: `testAddGarment`) launch against
//  `-astra-mock-backend` and assert real Closet behaviour.
//
//  DO NOT delete the remaining skips to make CI green — a deleted flow is
//  an invisible one.
//

import XCTest

/// `@MainActor` for the same reason as `ScreenQAUITests`: XCUITest's element
/// APIs are main-actor isolated in the iOS 26 SDK.
@MainActor
final class AstraStyleUITests: XCTestCase {
    // `lazy` rather than an implicitly-unwrapped `XCUIApplication!`: the IUO
    // form is only there to bridge "declared in the class, assigned in setUp",
    // and it trades a compile-time guarantee for a runtime trap (CLAUDE.md:
    // no force unwraps). `lazy` gives the same "created once per test instance"
    // behaviour with no optionality at all, and defers construction to first
    // use — which happens from a @MainActor context, matching XCUIApplication's
    // own isolation in the iOS 26 SDK.
    private lazy var app = XCUIApplication()

    /// How long to wait for a screen to appear. Longer on CI — same rationale
    /// as `OnboardingFlowUITests`.
    private let timeout: TimeInterval = ProcessInfo.processInfo.environment["CI"] == nil ? 20 : 60

    // Async overrides inherit the class's @MainActor isolation; the throwing
    // synchronous ones do not (see ScreenQAUITests for the full note).
    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments += [
            "-UITestMode", "1",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
    }

    @discardableResult
    private func awaitElement(
        _ element: XCUIElement,
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let found = element.waitForExistence(timeout: timeout)
        if !found {
            XCTFail("Never appeared: \(description)", file: file, line: line)
        }
        return found
    }

    /// Spec §22 "Complete onboarding". Owner: P2-ONBOARD.
    func testCompleteOnboarding() throws {
        throw XCTSkip(
            """
            Not implemented: drive Welcome -> Sign in with Apple (or guest) -> style goals -> style \
            identity -> measurements -> lifestyle -> preference quiz -> Style DNA result -> Home, \
            then assert the Daily Brief is visible. Owner: P2-ONBOARD.
            """
        )
    }

    /// Spec §22 "Add a garment" / P3-TEST-02 — manual entry via ClosetItemForm.
    ///
    /// Runs against `-astra-mock-backend` (in-memory `MockClosetRepository`)
    /// plus `-astra-skip-onboarding` so the Closet tab is reachable without
    /// walking §6.3–§6.10. Asserts the saved name appears in the closet
    /// grid and that detail shows a wear count of 0.
    func testAddGarment() throws {
        launchMockCloset()
        let closetTitle = app.staticTexts["My Closet"].firstMatch
        awaitElement(closetTitle, "Closet root")

        let itemName = "UI Test Oxford \(Int(Date().timeIntervalSince1970))"
        submitManualGarment(named: itemName)

        // The sheet must be gone before we tap Tops — while it is up,
        // XCUITest can hit the form's Tops *chip* (`closet.form.category.top`)
        // instead of the closet category tile (that was the prior CI miss).
        let formHeader = app.descendants(matching: .any)["closet.form.header"]
        XCTAssertTrue(
            formHeader.waitForNonExistence(timeout: timeout),
            "Add-garment sheet did not dismiss after submit — save likely failed"
        )
        awaitElement(closetTitle, "Closet root after save")

        // LazyVGrid below category tiles is off-screen — open Tops instead.
        let topsTile = app.descendants(matching: .any)["closet.category.top"]
        awaitElement(topsTile, "Tops category tile after save")
        topsTile.tap()

        let newTile = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "closet.grid.item.",
                itemName
            )
        ).firstMatch
        XCTAssertTrue(
            newTile.waitForExistence(timeout: timeout),
            "Saved garment '\(itemName)' did not appear in the Tops grid"
        )
        assertZeroWearCount(forTile: newTile, itemName: itemName)
    }

    private func launchMockCloset() {
        app.launchArguments += [
            "-astra-mock-backend",
            "-astra-skip-onboarding"
        ]
        app.launch()
        awaitElement(app.tabBars.firstMatch, "Main tab bar under mock backend")
        let closetTab = app.tabBars.buttons["Closet"]
        awaitElement(closetTab, "Closet tab")
        closetTab.tap()
    }

    private func submitManualGarment(named itemName: String) {
        let addButton = app.buttons["closet.header.addManually"]
        awaitElement(addButton, "Manual add button")
        addButton.tap()
        awaitElement(app.descendants(matching: .any)["closet.form.header"], "Add garment form")

        // Category first, while the keyboard is down — same lesson as
        // `OnboardingCaptureStepsUITests.testAddingAFirstItemAsAGuest`.
        let categoryChip = app.descendants(matching: .any)["closet.form.category.top"]
        awaitElement(categoryChip, "Tops category chip")
        categoryChip.tap()

        let nameField = app.descendants(matching: .any)["closet.form.name"]
        awaitElement(nameField, "Name field")
        nameField.tap()
        // Trailing newline resigns focus so the submit control is not
        // obscured by the keyboard when we tap it.
        nameField.typeText(itemName + "\n")

        let submit = app.descendants(matching: .any)["closet.form.submit"]
        awaitElement(submit, "Add garment submit")
        XCTAssertTrue(submit.isEnabled, "Submit should enable once name and category are set")
        submit.tap()
    }

    private func assertZeroWearCount(forTile newTile: XCUIElement, itemName: String) {
        newTile.tap()
        awaitElement(app.staticTexts[itemName].firstMatch, "Item detail name")
        let wornRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND value CONTAINS[c] %@", "Worn", "0 wear")
        ).firstMatch
        var swipes = 0
        while !wornRow.exists && swipes < 6 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(
            wornRow.waitForExistence(timeout: timeout),
            "Expected a wear count of 0 on the newly added garment"
        )
    }

    /// Spec §22 "Generate outfit". Owner: P4-OUTFIT.
    func testGenerateOutfit() throws {
        throw XCTSkip(
            "Not implemented: trigger outfit generation from Home or the builder and assert three ranked outfits render, each with a non-empty 'why it works' reason. Owner: P4-OUTFIT."
        )
    }

    /// Spec §22 "Mark worn". Owner: P4-OUTFIT.
    func testMarkOutfitWorn() throws {
        throw XCTSkip(
            """
            Not implemented: tap 'Wear This' on the Home hero card and assert the outfit's wear \
            count increments and a success haptic/confirmation is shown (spec §3 Motion: 'success \
            for saved closet scan' pattern applies analogously here). Owner: P4-OUTFIT.
            """
        )
    }

    /// Spec §22 "Ask Kyra". Owner: P5-KYRA.
    func testAskKyra() throws {
        throw XCTSkip(
            "Not implemented: open the Ask Kyra modal, send a message, and assert a structured response renders (not raw unformatted text) with at least one suggested action. Owner: P5-KYRA."
        )
    }

    /// Spec §22 "Open paywall and restore purchases". Owner: P7-SUB.
    func testOpenPaywallAndRestorePurchases() throws {
        throw XCTSkip(
            """
            Not implemented: trigger a paywall context (e.g. closet limit), assert monthly/annual \
            plans and Restore Purchases are visible, then assert Restore Purchases completes without \
            error against a StoreKit sandbox configuration. Owner: P7-SUB.
            """
        )
    }

    /// Spec §22 "Delete account". Owner: P7-SUB (flow) / P1-CORE (underlying `DELETE /account`).
    func testDeleteAccount() throws {
        throw XCTSkip(
            "Not implemented: drive Profile -> Privacy and Data -> Delete Account through its confirmation step and assert the app returns to the signed-out Welcome screen. Owner: P7-SUB."
        )
    }
}
