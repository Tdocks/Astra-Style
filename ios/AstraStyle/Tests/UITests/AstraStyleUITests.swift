//
//  AstraStyleUITests.swift
//  AstraStyleUITests
//
//  Spec §22 "UI tests" — XCUITest (not Swift Testing; UI automation still
//  needs `XCTest`/`XCUIApplication` even in an otherwise Swift-Testing
//  codebase, per the build instructions).
//
//  Every test below is an unwritten placeholder: the screens they need to
//  drive (onboarding, closet, outfit generation, Kyra, paywall, account
//  deletion) are still `FeaturePlaceholderView` stand-ins (see
//  MainTabView.swift / each feature's README). Each `XCTSkip` names the real
//  assertion the test should make once its feature module lands, so the gap
//  shows up in Xcode/CI's test report rather than being silently missing.
//
//  These were originally `XCTFail("Not implemented: …")` bodies — deliberate
//  failures, chosen so the gap would be unmissable. They are now `XCTSkip`
//  with the same messages, verbatim, for one reason: a suite that can never
//  be green is a suite nobody reads. Seven permanent red tests do not
//  communicate "seven flows are unwritten", they communicate "this job is
//  always red", and they make every OTHER failure — a real regression, the
//  P1-INFRA-03 requirement that CI fails on a warning or lint violation —
//  unverifiable, because the job was already failing. A skip carrying the
//  identical message says exactly the same thing without spending the signal,
//  and the day someone writes a body it starts counting as a real test.
//
//  `XCTSkip`, not `XCTExpectFailure`: `XCTExpectFailure` is for a WRITTEN
//  test that currently fails, and it fails the run if the failure stops
//  occurring. There is nothing written here to expect a failure from — a body
//  whose only statement is "not implemented" is honestly a skip.
//
//  DO NOT delete these to make CI green — a deleted flow is an invisible one.
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

    // Async overrides inherit the class's @MainActor isolation; the throwing
    // synchronous ones do not (see ScreenQAUITests for the full note).
    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments += ["-UITestMode", "1"]
    }

    // Each test throws its skip BEFORE `app.launch()`. Launching a simulator
    // only to abandon it costs ~10s per test and proves nothing, since no
    // assertion follows it; the launch belongs in whichever commit writes the
    // body. `app` is still configured in `setUp` above so that the launch
    // arguments stay attached to the flow they describe.

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

    /// Spec §22 "Add a garment". Owner: P3-CLOSET / P3-SCAN.
    func testAddGarment() throws {
        throw XCTSkip(
            """
            Not implemented: drive the scan flow (or manual entry) to completion and assert the new \
            item appears in the Closet grid with a non-empty wear count of 0 and an editable, \
            non-placeholder name. Owner: P3-CLOSET / P3-SCAN.
            """
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
