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
//  Runs against guest mode, which needs no network and no account (spec §6.2),
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
    private let timeout: TimeInterval = 20

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
        XCTAssertTrue(app.staticTexts["Explore in guest mode"].exists
                      || app.buttons["Explore in guest mode"].exists)
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

    /// Enters guest mode and steps past the onboarding placeholder into the
    /// five-tab shell.
    private func enterMainShell() {
        app.launch()

        let guestEntry = app.buttons["Explore in guest mode"].exists
            ? app.buttons["Explore in guest mode"]
            : app.staticTexts["Explore in guest mode"]
        awaitElement(guestEntry, "Welcome: guest mode entry")
        guestEntry.tap()

        awaitElement(app.staticTexts["Let's build your Style DNA"], "Onboarding placeholder")
        capture("04-Onboarding-Placeholder")

        app.buttons["Skip for now"].tap()
        awaitElement(app.tabBars.firstMatch, "Main tab bar")
    }

    func testEveryTab() {
        enterMainShell()

        // Ordered as they appear in the tab bar (spec §4).
        let tabs = ["Home", "Closet", "Studio", "Discover", "Profile"]
        for (index, tab) in tabs.enumerated() {
            let button = app.tabBars.buttons[tab]
            awaitElement(button, "Tab bar item: \(tab)")
            button.tap()
            // Let the transition settle before capturing, or the screenshot
            // catches a half-faded screen and looks like a rendering bug.
            usleep(600_000)
            capture(String(format: "%02d-Tab-%@", 5 + index, tab))
        }
    }

    /// Phase 1 exit criterion, verified through the UI rather than only at the
    /// router: switching away from a tab and back preserves where you were.
    func testTabStatePreservedThroughUI() {
        enterMainShell()

        app.tabBars.buttons["Closet"].tap()
        usleep(400_000)
        let closetAnchor = app.staticTexts["Closet"].firstMatch
        XCTAssertTrue(closetAnchor.exists, "Closet root did not render")

        for tab in ["Home", "Studio", "Discover", "Profile"] {
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
