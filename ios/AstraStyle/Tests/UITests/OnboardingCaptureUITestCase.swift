//
//  OnboardingCaptureUITestCase.swift
//  AstraStyleUITests
//
//  Shared plumbing for the §5.1 steps 11 and 12 suites: the walk from launch
//  to the reference photo step, and the retry-and-scroll helpers that walk
//  needs at the largest text size.
//
//  A BASE CLASS RATHER THAN A LONGER FILE. Both steps lived in
//  `OnboardingCaptureStepsUITests` until the first-items step gained its photo
//  path (`P2-ONBOARD-13`), at which point the class crossed SwiftLint's
//  `type_body_length` limit. `.swiftlint.yml`'s header forbids raising a
//  threshold to accommodate new code, and the split falls naturally by step:
//  the reference photo is tested for whether a consent gate holds, first items
//  for whether a man can get PAST the step. The walk that reaches both is the
//  only thing the two suites share, so it is the only thing in here.
//
//  WHAT CANNOT BE COVERED BY ANYTHING BUILT ON THIS FILE, STATED PLAINLY. No
//  camera path is exercised. A simulator has no camera, so
//  `ReferenceCameraPicker.isAvailable` is false and the "Take one now" button
//  is correctly absent — which those tests assert, because offering a control
//  that fails on tap is the dead control §22 forbids. The system photo picker
//  is out of process and cannot be driven from XCUITest without a fixture
//  library, so no test here selects an actual image.
//

import XCTest

/// `@MainActor` because every `XCUIApplication` member is main-actor isolated
/// in the iOS 26 SDK.
@MainActor
class OnboardingCaptureUITestCase: XCTestCase {
    lazy var app = XCUIApplication()

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
    let timeout: TimeInterval = ProcessInfo.processInfo.environment["CI"] == nil ? 20 : 60

    override func setUp() async throws {
        continueAfterFailure = true
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-astra-reset-state",
            "-astra-full-onboarding"
        ]
    }

    // MARK: - Plumbing

    func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @discardableResult
    func awaitElement(
        _ element: XCUIElement,
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let found = element.waitForExistence(timeout: timeout)
        if !found { XCTFail("Never appeared: \(description)", file: file, line: line) }
        return found
    }

    /// Matched by identifier alone, whichever element type XCUITest infers.
    ///
    /// `PhotosPicker` and a container carrying `.accessibilityElement(children:
    /// .contain)` do not reliably surface as `.button` or `.other` — the type
    /// depends on what is inside them, which is content. The identifier is what
    /// these assertions actually mean.
    func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Enters onboarding against the in-memory mocks and walks to the reference photo step,
    /// answering only §6.5 — the one step the flow requires.
    func walkToReferenceStep(largestTextSize: Bool = false) {
        if largestTextSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        // Before `launch()`, obviously — but worth stating, because the
        // guest tap this replaced happened after it and moving the line
        // without moving it far enough would silently launch signed out.
        app.launchArguments += ["-astra-mock-backend"]
        app.launch()

        awaitElement(app.buttons["onboarding.begin"], "Intro")
        app.buttons["onboarding.begin"].tap()

        let choice = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Men's looks")
        ).firstMatch
        awaitElement(choice, "Wardrobe graph")
        XCTAssertFalse(
            app.buttons["onboarding.advance"].isEnabled,
            "Wardrobe graph is required but Continue is enabled before a choice"
        )
        choice.tap()
        XCTAssertTrue(choice.waitUntilSelected(), "Wardrobe graph choice never selected")
        app.buttons["onboarding.advance"].tap()

        awaitElement(app.buttons["onboarding.advance"], "Goals")
        app.buttons["onboarding.advance"].tap()

        awaitElement(app.buttons["onboarding.identity.quiet_luxury"], "Identity")
        // Walk to the end of the grid first. At AX5 the grid is one column and
        // several screens tall, so a card whose top edge is visible can have
        // its CENTRE — where XCUITest aims — under the footer; reaching each
        // card by scrolling back UP puts it mid-viewport before it is tapped.
        // Paid for in `OnboardingFlowUITests`; repeated here for the same
        // reason rather than rediscovered.
        usleep(600_000)
        app.swipeUp(velocity: .slow)
        usleep(400_000)
        app.buttons["onboarding.identity.creative"].scrollIntoView(in: app)
        // The same three, in the same order, as `OnboardingFlowUITests`'
        // AX5 walk. Not arbitrary: after scrolling to the END of the grid,
        // `scrollIntoView` reaches each of these by scrolling back UP, which
        // puts the card mid-viewport before it is tapped. A different triple
        // failed here on `minimalist` for exactly that reason.
        for identity in ["smart_casual", "modern_heritage", "quiet_luxury"] {
            selectIdentityCard(identity)
        }
        XCTAssertTrue(app.buttons["onboarding.advance"].isEnabled, "The §6.5 gate never opened")
        app.buttons["onboarding.advance"].tap()

        for step in ["measurements", "appearance", "lifestyle", "quiz"] {
            let forward = app.buttons["onboarding.advance"]
            guard awaitElement(forward, "Forward button on \(step)") else { return }
            forward.waitForStableFrame()
            forward.tap()
            usleep(400_000)
        }
    }

    /// Skips the reference step, waiting for its forward button to settle
    /// first. Tapping it while the step is still animating in is a tap the
    /// system spends on stopping the transition, which leaves the flow one
    /// screen behind where the test believes it is.
    func leaveReferenceStep() {
        let forward = app.buttons["onboarding.advance"]
        awaitElement(forward, "Reference: forward button")
        forward.waitForStableFrame()
        forward.tap()
        usleep(500_000)
    }

    /// Ticks the §29 acknowledgment and confirms it took.
    ///
    /// Retries for the same reason `selectIdentityCard` does, and it is not
    /// defensive padding: iOS spends the first tap on a still-decelerating
    /// scroll view rather than on the button underneath it, and at AX5 this
    /// control sits at the bottom of a page several screens long, so every tap
    /// on it follows a scroll. Waits five seconds for the trait rather than
    /// three, because acknowledging re-lays out the whole step — the capture
    /// controls appear beneath it — and the accessibility tree is rebuilt after
    /// that, not before.
    func acknowledgeConsent(file: StaticString = #filePath, line: UInt = #line) {
        let consent = app.buttons["onboarding.reference.consent"]
        for _ in 1...3 {
            consent.scrollIntoView(in: app)
            // Then keep going to the true bottom of the page. `scrollIntoView`
            // stops the moment the control is hittable, which at AX5 is the
            // moment it first peeks above the fold — and at that point its
            // CENTRE, where XCUITest aims, is still under the footer, so the
            // tap lands on the chrome and the checkbox never changes. Scrolling
            // to the end puts it above the footer, because `safeAreaInset`
            // insets the scroll content by the footer's actual height. Same
            // failure and same fix as the identity grid at this text size.
            for _ in 0..<5 { app.swipeUp(velocity: .slow) }
            usleep(500_000)
            guard consent.exists, consent.isHittable else { continue }
            consent.waitForStableFrame()
            consent.tap()
            if consent.waitUntilSelected(timeout: 5) { return }
        }
        XCTFail("The consent acknowledgment never registered", file: file, line: line)
    }

    func selectIdentityCard(
        _ identity: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let card = app.buttons["onboarding.identity.\(identity)"]
        for _ in 1...3 {
            card.scrollIntoView(in: app)
            guard card.exists else { continue }
            card.waitForStableFrame()
            guard card.isHittable else { continue }
            card.tap()
            if card.waitUntilSelected() { return }
        }
        XCTFail("Identity card never became selected: \(identity)", file: file, line: line)
    }

    // MARK: - Scrolling helpers

    /// Scrolls down then back up looking for an element, asserting only that it
    /// EXISTS — a container with no tap action of its own never has to be
    /// hittable, and the question for one is whether the user can reach it.
    @discardableResult
    func scrollUntilPresent(_ element: XCUIElement, maxSwipes: Int = 14) -> Bool {
        if element.exists { return true }
        for _ in 0..<maxSwipes {
            app.swipeUp(velocity: .slow)
            usleep(200_000)
            if element.exists { return true }
        }
        for _ in 0..<maxSwipes {
            app.swipeDown(velocity: .slow)
            usleep(200_000)
            if element.exists { return true }
        }
        return element.exists
    }
}
