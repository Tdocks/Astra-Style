//
//  AstraStyleUITests.swift
//  AstraStyleUITests
//
//  Spec §22 "UI tests" — XCUITest (not Swift Testing; UI automation still
//  needs `XCTest`/`XCUIApplication` even in an otherwise Swift-Testing
//  codebase, per the build instructions).
//
//  Every test below is an INTENTIONALLY FAILING placeholder: the screens
//  they need to drive (onboarding, closet, outfit generation, Kyra,
//  paywall, account deletion) are still `FeaturePlaceholderView` stand-ins
//  (see MainTabView.swift / each feature's README). `XCTFail` names the
//  real assertion each test should make once its feature module lands, so
//  the gap shows up as a red test in Xcode/CI rather than a silently
//  missing test.
//

import XCTest

/// `@MainActor` for the same reason as `ScreenQAUITests`: XCUITest's element
/// APIs are main-actor isolated in the iOS 26 SDK.
@MainActor
final class AstraStyleUITests: XCTestCase {
    private var app: XCUIApplication!

    // Async overrides inherit the class's @MainActor isolation; the throwing
    // synchronous ones do not (see ScreenQAUITests for the full note).
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "1"]
    }

    override func tearDown() async throws {
        app = nil
    }

    /// Spec §22 "Complete onboarding". Owner: P2-ONBOARD.
    func testCompleteOnboarding() throws {
        app.launch()
        XCTFail(
            "Not implemented: drive Welcome -> Sign in with Apple (or guest) -> style goals -> style identity -> measurements -> lifestyle -> preference quiz -> Style DNA result -> Home, then assert the Daily Brief is visible. Owner: P2-ONBOARD."
        )
    }

    /// Spec §22 "Add a garment". Owner: P3-CLOSET / P3-SCAN.
    func testAddGarment() throws {
        app.launch()
        XCTFail(
            "Not implemented: drive the scan flow (or manual entry) to completion and assert the new item appears in the Closet grid with a non-empty wear count of 0 and an editable, non-placeholder name. Owner: P3-CLOSET / P3-SCAN."
        )
    }

    /// Spec §22 "Generate outfit". Owner: P4-OUTFIT.
    func testGenerateOutfit() throws {
        app.launch()
        XCTFail(
            "Not implemented: trigger outfit generation from Home or the builder and assert three ranked outfits render, each with a non-empty 'why it works' reason. Owner: P4-OUTFIT."
        )
    }

    /// Spec §22 "Mark worn". Owner: P4-OUTFIT.
    func testMarkOutfitWorn() throws {
        app.launch()
        XCTFail(
            "Not implemented: tap 'Wear This' on the Home hero card and assert the outfit's wear count increments and a success haptic/confirmation is shown (spec §3 Motion: 'success for saved closet scan' pattern applies analogously here). Owner: P4-OUTFIT."
        )
    }

    /// Spec §22 "Ask Kyra". Owner: P5-KYRA.
    func testAskKyra() throws {
        app.launch()
        XCTFail(
            "Not implemented: open the Ask Kyra modal, send a message, and assert a structured response renders (not raw unformatted text) with at least one suggested action. Owner: P5-KYRA."
        )
    }

    /// Spec §22 "Open paywall and restore purchases". Owner: P7-SUB.
    func testOpenPaywallAndRestorePurchases() throws {
        app.launch()
        XCTFail(
            "Not implemented: trigger a paywall context (e.g. closet limit), assert monthly/annual plans and Restore Purchases are visible, then assert Restore Purchases completes without error against a StoreKit sandbox configuration. Owner: P7-SUB."
        )
    }

    /// Spec §22 "Delete account". Owner: P7-SUB (flow) / P1-CORE (underlying `DELETE /account`).
    func testDeleteAccount() throws {
        app.launch()
        XCTFail(
            "Not implemented: drive Profile -> Privacy and Data -> Delete Account through its confirmation step and assert the app returns to the signed-out Welcome screen. Owner: P7-SUB."
        )
    }
}
