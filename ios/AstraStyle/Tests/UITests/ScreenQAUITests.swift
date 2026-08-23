//
//  ScreenQAUITests.swift
//  AstraStyleUITests
//
//  A visual QA sweep: walk every screen the app can currently reach and
//  capture a screenshot of each, so the whole surface can be reviewed at once
//  rather than one screen at a time.
//
//  These are deliberately NOT assertions about pixels. Snapshot-diff testing
//  at this stage would fail on every intentional design change and teach the
//  team to ignore it. What these DO assert is that each screen is reachable
//  and renders its expected anchor content — a screen that silently stopped
//  loading would fail here, and the attached screenshot says why.
//
//  Screenshots land in the .xcresult bundle. Extract them with:
//
//      xcrun xcresulttool export attachments \
//        --path <result>.xcresult --output-path ./shots
//
//  Runs against the in-memory mocks, which need no network and no account,
//  so the sweep works on a clean simulator with no fixtures.
//

import XCTest

/// `@MainActor` because every `XCUIApplication`/`XCUIElement` member is
/// main-actor isolated in the iOS 26 SDK. Without it this file produced 85
/// concurrency warnings — and CI builds with warnings-as-errors, so they are
/// build failures, not noise.
@MainActor
final class ScreenQAUITests: XCTestCase {
    // `lazy` rather than an implicitly-unwrapped `XCUIApplication!`: the IUO
    // form is only there to bridge "declared in the class, assigned in setUp",
    // and it trades a compile-time guarantee for a runtime trap (CLAUDE.md:
    // no force unwraps). `lazy` gives the same "created once per test instance"
    // behaviour with no optionality at all, and defers construction to first
    // use — which happens from a @MainActor context, matching XCUIApplication's
    // own isolation in the iOS 26 SDK.
    private lazy var app = XCUIApplication()

    /// Generous, because the splash deliberately holds a 450ms floor before
    /// routing (spec §6.1) and a cold launch on CI is slower than on a laptop.
    /// How long to wait for a screen to appear.
    ///
    /// Longer on CI, and the difference is not padding. A GitHub runner is a
    /// shared, loaded machine booting a cold simulator, and the first test in a
    /// suite pays for that boot on top of whatever it is actually asserting —
    /// `testBackPreservesAnswers` failed at 20s on CI with "Never appeared:
    /// Goals" while passing locally in a fraction of it, having burned 91
    /// seconds of wall clock getting nowhere.
    ///
    /// Raising it everywhere would have been the lazy fix: a local run would
    /// then take 60s to tell you a screen is genuinely broken, which is the
    /// feedback loop that matters most and the one worth keeping fast. So the
    /// developer keeps a tight 20s and CI gets the slack it actually needs.
    ///
    /// `CI` is set by GitHub Actions. The test-runner process inherits it from
    /// `xcodebuild`, so this reads correctly there and is absent locally.
    private let timeout: TimeInterval = ProcessInfo.processInfo.environment["CI"] == nil ? 20 : 60

    // `setUp() async throws` rather than `setUpWithError()`: the throwing
    // synchronous override is nonisolated even on a @MainActor class, so
    // touching `app` from it warns under strict concurrency. The async variant
    // inherits the class's isolation.
    override func setUp() async throws {
        continueAfterFailure = true
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            // Start every sweep signed out. Without this the run inherits
            // whatever session the last manual launch left in the Keychain,
            // which is how the first attempt at this sweep opened on Home and
            // failed every assertion for the wrong reason.
            "-astra-reset-state"
        ]
    }

    // MARK: - Capture helper

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        // `.keepAlways`, otherwise Xcode discards attachments for passing
        // tests — which is exactly the case we want the screenshots from.
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Waits for an element and fails with a useful message rather than a bare
    /// timeout, so a broken screen names itself in the log.
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

    // MARK: - Entry surfaces

    func testWelcomeScreen() {
        app.launch()

        awaitElement(app.buttons["Continue with Apple"], "Welcome: Sign in with Apple button")
        capture("01-Welcome")

        // Spec §6.2 requires Terms and Privacy reachable before account
        // creation; App Store review checks for this too.
        //
        // SwiftUI's `Link` surfaces as a `.button` in the accessibility
        // tree, not a `.link` — `app.links[...]` never matched it even
        // though the links are genuinely present and visible. Target the
        // stable `accessibilityIdentifier`s `RootView.swift` sets instead.
        XCTAssertTrue(app.buttons["welcome.termsLink"].exists, "Terms link missing from Welcome")
        XCTAssertTrue(app.buttons["welcome.privacyLink"].exists, "Privacy link missing from Welcome")
        XCTAssertTrue(app.buttons["Continue with Email"].exists)
        // Two actions and no third. ADR 0014 removed "Explore in guest
        // mode"; asserting on its ABSENCE is what stops it coming back by
        // accident, which a missing positive assertion would not.
        XCTAssertFalse(app.staticTexts["Explore in guest mode"].exists)
        XCTAssertFalse(app.buttons["Explore in guest mode"].exists)
    }

    func testEmailAuthSheet() {
        app.launch()
        awaitElement(app.buttons["Continue with Email"], "Welcome: email button")
        app.buttons["Continue with Email"].tap()

        awaitElement(app.staticTexts["What's your email?"], "Email sheet: prompt")
        capture("02-EmailAuth-EnterEmail")

        // The primary action must be disabled until the input is plausible —
        // a "Send Code" that fires on an empty field is a dead end.
        let sendCode = app.buttons["Send Code"]
        if sendCode.exists {
            XCTAssertFalse(sendCode.isEnabled, "Send Code should be disabled with an empty email")
        }

        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("qa@astrastyle.app")
            capture("03-EmailAuth-Filled")
            XCTAssertTrue(sendCode.isEnabled, "Send Code should enable once an email is entered")
        }
    }

    // MARK: - Main shell

    /// Lands in the dogfood tab shell (Home, Closet, Discover, Profile).
    ///
    /// Deliberately does NOT walk §6.3–§6.10. It used to, back when onboarding
    /// was a single placeholder screen with one "Skip for now" button, and that
    /// coupling is what broke this file: the moment onboarding became eight real
    /// steps with a required §6.5 gate, two tests about TAB NAVIGATION started
    /// failing on an onboarding string. Repairing them by walking the real eight
    /// screens would rebuild the same coupling with better selectors — every
    /// future change to the flow would still land here first, on tests whose
    /// subject it is not.
    ///
    /// So the shell is entered through `-astra-skip-onboarding`
    /// (`AstraFeatureFlags.skipsOnboarding`, Debug builds only) instead. The
    /// flow itself is walked end to end by `OnboardingFlowUITests`, which also
    /// asserts that finishing it arrives in this same tab shell — so the
    /// onboarding-to-main transition is still covered, once, by the test that
    /// is actually about onboarding.
    ///
    /// Reached through `-astra-mock-backend`, which starts already signed in
    /// against `Core/Mocks`. This used to tap "Explore in guest mode" — the
    /// only account-free entry there was — which ADR 0014 removed.
    private func enterMainShell() {
        app.launchArguments += ["-astra-mock-backend", "-astra-skip-onboarding"]
        app.launch()

        awaitElement(app.tabBars.firstMatch, "Main tab bar")
        capture("04-MainShell-Entered")
    }

    func testEveryTab() {
        enterMainShell()

        // Ordered as they appear in the dogfood tab bar.
        let tabs = ["Home", "Closet", "Studio", "Discover", "Shop", "Profile"]
        for (index, tab) in tabs.enumerated() {
            let button = app.tabBars.buttons[tab]
            awaitElement(button, "Tab bar item: \(tab)")
            button.tap()
            usleep(600_000)
            capture(String(format: "%02d-Tab-%@", 5 + index, tab))
        }
        XCTAssertTrue(
            app.tabBars.buttons["Studio"].exists,
            "Studio belongs on the bar as the generation gallery"
        )
        XCTAssertTrue(
            app.tabBars.buttons["Shop"].exists,
            "Shop is the curated catalog tab"
        )
    }

    /// Phase 1 exit criterion, verified through the UI rather than only at the
    /// router: switching away from a tab and back preserves where you were.
    func testTabStatePreservedThroughUI() {
        enterMainShell()

        app.tabBars.buttons["Closet"].tap()
        usleep(400_000)
        // "My Closet" is the real screen's title (spec §6.14). This used to
        // anchor on "Closet", which was the `FeaturePlaceholderView` title
        // AND the tab bar item's label — so the assertion passed on the tab
        // button whether or not the screen behind it rendered at all. A tab
        // label is not evidence that a tab's content loaded.
        let closetAnchor = app.staticTexts["My Closet"].firstMatch
        awaitElement(closetAnchor, "Closet root")

        for tab in ["Home", "Profile"] {
            app.tabBars.buttons[tab].tap()
            usleep(200_000)
        }

        app.tabBars.buttons["Closet"].tap()
        usleep(400_000)
        capture("10-TabState-ReturnedToCloset")
        XCTAssertTrue(closetAnchor.exists, "Closet did not restore after switching away and back")
    }

    // MARK: - Accessibility sweeps

    /// Spec §19 requires full Dynamic Type support. The largest accessibility
    /// size is where fixed-height rows and truncation problems surface, and it
    /// is the size least likely to be checked by hand.
    func testLargestDynamicTypeSize() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        awaitElement(app.buttons["Continue with Apple"], "Welcome at AX5")
        capture("11-Welcome-DynamicType-AX5")
    }

    /// Spec §3 lists a full light palette, and the contrast audit in
    /// docs/07-design-system.md found a real failure there — so light mode
    /// needs eyes on it, not just a token table.
    func testLightAppearance() {
        // `-UIUserInterfaceStyle` alone is not enough: the app applies its own
        // `.preferredColorScheme(...)`, which correctly overrides the system
        // setting. `-astra-theme` drives the app's preference itself, which is
        // the only way to actually reach the light palette.
        app.launchArguments += ["-astra-theme", "light"]
        app.launch()

        awaitElement(app.buttons["Continue with Apple"], "Welcome in light mode")
        capture("12-Welcome-LightMode")
    }
}
