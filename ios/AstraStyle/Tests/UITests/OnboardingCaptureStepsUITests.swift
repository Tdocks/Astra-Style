//
//  OnboardingCaptureStepsUITests.swift
//  AstraStyleUITests
//
//  §5.1 steps 11 and 12 — the reference photo and the first closet items.
//
//  A suite of their own rather than more methods on `OnboardingFlowUITests`,
//  for two reasons. The obvious one is length: that file already walks eight
//  screens and hardens three of them at AX5. The better one is that these two
//  steps are tested for different things than the rest of the flow. Every
//  other step is checked for "does it render and can it be answered"; these
//  two are checked for "can the user get PAST it" and "does the §29 gate hold",
//  which are the two properties whose failure would not look like a bug on the
//  screen where it happened.
//
//  WHAT CANNOT BE COVERED HERE, STATED PLAINLY. The camera path is not
//  exercised. A simulator has no camera, so `ReferenceCameraPicker.isAvailable`
//  is false and the "Take one now" button is correctly absent — which these
//  tests assert, since offering it would be a dead control. The system photo
//  picker is also out of process and cannot be driven from XCUITest without
//  a fixture library, so no test here selects an actual image; the consent
//  gate in front of it is what is covered, and `OnboardingReferenceTests`
//  covers what happens to the bytes once there are some.
//

import XCTest

/// `@MainActor` because every `XCUIApplication` member is main-actor isolated
/// in the iOS 26 SDK.
@MainActor
final class OnboardingCaptureStepsUITests: XCTestCase {
    private lazy var app = XCUIApplication()
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

    override func setUp() async throws {
        continueAfterFailure = true
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-astra-reset-state"
        ]
    }

    // MARK: - Plumbing

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

    /// Matched by identifier alone, whichever element type XCUITest infers.
    ///
    /// `PhotosPicker` and a container carrying `.accessibilityElement(children:
    /// .contain)` do not reliably surface as `.button` or `.other` — the type
    /// depends on what is inside them, which is content. The identifier is what
    /// these assertions actually mean.
    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Enters onboarding against the in-memory mocks and walks to the reference photo step,
    /// answering only §6.5 — the one step the flow requires.
    private func walkToReferenceStep(largestTextSize: Bool = false) {
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
    private func leaveReferenceStep() {
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
    private func acknowledgeConsent(file: StaticString = #filePath, line: UInt = #line) {
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

    private func selectIdentityCard(
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

    // MARK: - §5.1 step 11 — consent before capture

    /// The ticket's second acceptance criterion, and the only one a UI test
    /// can settle: the explanation is on screen, and no capture control exists
    /// until it has been acknowledged.
    func testConsentIsRequiredBeforeAnyCaptureControlAppears() {
        walkToReferenceStep()

        awaitElement(app.buttons["onboarding.reference.consent"], "Reference: acknowledgment control")
        XCTAssertTrue(
            anyElement("onboarding.reference.consentPanel").exists,
            "The step that collects a photograph of the user shows no explanation of what happens to it"
        )
        XCTAssertFalse(
            anyElement("onboarding.reference.choosePhoto").exists,
            "A photo picker is offered before consent has been acknowledged"
        )
        // Correctly absent on a simulator, which has no camera. Asserted rather
        // than ignored: the alternative implementation offers the button
        // everywhere and fails on tap, which is the dead control §22 forbids.
        XCTAssertFalse(
            app.buttons["onboarding.reference.takePhoto"].exists,
            "The camera control is offered on a device with no camera"
        )
        capture("50-Reference-BeforeConsent")

        acknowledgeConsent()

        XCTAssertTrue(
            scrollUntilPresent(anyElement("onboarding.reference.choosePhoto")),
            "Consent was acknowledged and no capture control appeared, so the step cannot be completed"
        )
        capture("51-Reference-AfterConsent")

        let consent = app.buttons["onboarding.reference.consent"]

        // The gate has to work in both directions, or it is a one-way door
        // dressed as a checkbox.
        consent.scrollIntoView(in: app)
        consent.waitForStableFrame()
        consent.tap()
        // Polled rather than slept on: the control disappearing is a re-render,
        // and a fixed sleep either wastes time or reads the tree from before it.
        let deadline = Date().addingTimeInterval(5)
        while anyElement("onboarding.reference.choosePhoto").exists, Date() < deadline {
            usleep(200_000)
        }
        XCTAssertFalse(
            anyElement("onboarding.reference.choosePhoto").exists,
            "Withdrawing consent left the capture controls on screen"
        )
        capture("52-Reference-ConsentWithdrawn")
    }

    /// Spec §19 at the largest text size, on the screen where the consequence
    /// of an unreachable control is that a man cannot decline — or accept —
    /// something he was asked about his own photograph.
    func testReferenceStepAtLargestDynamicType() {
        walkToReferenceStep(largestTextSize: true)

        awaitElement(app.buttons["onboarding.reference.consent"], "Reference: consent at AX5")
        usleep(700_000)
        capture("53-Reference-AX5")

        XCTAssertTrue(
            scrollUntilPresent(anyElement("onboarding.reference.consentPanel")),
            "The consent explanation cannot be reached by scrolling at AX5"
        )

        let consent = app.buttons["onboarding.reference.consent"]
        consent.scrollIntoView(in: app)
        XCTAssertTrue(
            consent.exists && consent.isHittable,
            "The acknowledgment control is unreachable at AX5, so the step cannot be completed"
        )
        capture("53b-Reference-AX5-consentControl")

        acknowledgeConsent()
        XCTAssertTrue(
            scrollUntilPresent(anyElement("onboarding.reference.choosePhoto")),
            "The photo control is unreachable at AX5 after consent"
        )
        capture("53c-Reference-AX5-consented")

        // Back to the top, proving the page scrolls both ways at this size,
        // then the control that leaves the step.
        for _ in 0..<20 { app.swipeDown(velocity: .slow) }
        usleep(400_000)
        let forward = app.buttons["onboarding.advance"]
        XCTAssertTrue(
            forward.exists && forward.isHittable && forward.isEnabled,
            "The reference step cannot be left at AX5"
        )
    }

    // MARK: - §5.1 step 12 — adding and skipping

    func testAddingAFirstItem() {
        walkToReferenceStep()
        leaveReferenceStep()

        awaitElement(app.buttons["onboarding.firstItems.add"], "First items: add button")
        XCTAssertFalse(
            app.buttons["onboarding.firstItems.add"].isEnabled,
            "Add is enabled with an empty form, so tapping it can only fail"
        )
        capture("54-FirstItems-Empty")

        // ORDER MATTERS, AND IT COST A DEBUGGING SESSION. The category chips
        // are tapped FIRST, while no keyboard is up.
        //
        // With the keyboard raised, the scaffold's `safeAreaInset` footer sits
        // directly above it and is drawn over the form. A chip whose top edge
        // is still visible can have its CENTRE — where XCUITest aims — under
        // that footer, and the tap lands on "Back" instead: the app returned to
        // the reference step, every later query found nothing, and the failure
        // surfaced twenty seconds later as "the colour field does not exist".
        // Same shape as the identity-grid gotcha, different container.
        let category = app.buttons["onboarding.firstItems.category.top"]
        category.scrollIntoView(in: app)
        category.waitForStableFrame()
        category.tap()
        XCTAssertTrue(category.waitUntilSelected(), "The category chip never became selected")

        // Each field is submitted with a newline, which resigns focus and puts
        // the keyboard away — so the next element is tapped against a layout
        // that is not about to move.
        let name = app.textFields["onboarding.firstItems.name"]
        name.scrollIntoView(in: app)
        name.tap()
        name.typeText("Navy merino crewneck\n")

        let color = app.textFields["onboarding.firstItems.color"]
        color.scrollIntoView(in: app)
        color.tap()
        color.typeText("navy\n")

        let add = app.buttons["onboarding.firstItems.add"]
        add.scrollIntoView(in: app)
        XCTAssertTrue(add.isEnabled, "A named, categorised item still cannot be added")
        add.waitForStableFrame()
        add.tap()

        // The row is the only evidence the user has that the write landed; a
        // confirmation message alone would be the app telling him rather than
        // showing him.
        XCTAssertTrue(
            scrollUntilPresent(anyElement("onboarding.firstItems.list")),
            "The added item never appeared in the list"
        )
        XCTAssertTrue(
            scrollUntilPresent(app.staticTexts["Navy merino crewneck"]),
            "The added item is not named anywhere on screen"
        )
        capture("55-FirstItems-Added")

        for _ in 0..<10 { app.swipeDown(velocity: .slow) }
        usleep(400_000)
        XCTAssertEqual(
            app.buttons["onboarding.advance"].label, "Continue",
            "An item was added, so the forward button should continue rather than skip"
        )
    }

    /// Phase 2's last exit criterion, as its own test so a failure names it
    /// rather than reporting "the result screen never appeared".
    func testSkippingFirstItemsStillReachesHome() {
        walkToReferenceStep()

        for step in ["reference", "firstItems"] {
            let forward = app.buttons["onboarding.advance"]
            guard awaitElement(forward, "Forward button on \(step)") else { return }
            XCTAssertTrue(forward.isEnabled, "\(step) is optional but its forward button is disabled")
            XCTAssertNotEqual(
                forward.label, "Continue",
                "Nothing was added to \(step), so the forward button should offer to skip"
            )
            forward.waitForStableFrame()
            forward.tap()
            usleep(400_000)
        }

        awaitElement(app.buttons["onboarding.advance"], "Result after skipping both steps")
        capture("56-SkippedBothSteps-Result")

        app.buttons["onboarding.advance"].tap()
        awaitElement(app.tabBars.firstMatch, "Home after skipping both capture steps")
        capture("57-SkippedBothSteps-Home")
    }

    /// Spec §19 on the longest form in the flow at the largest text size: a
    /// title, three labelled fields, seven category chips and a button.
    func testFirstItemsAtLargestDynamicType() {
        walkToReferenceStep(largestTextSize: true)
        leaveReferenceStep()

        awaitElement(app.buttons["onboarding.firstItems.add"], "First items at AX5")
        usleep(700_000)
        capture("58-FirstItems-AX5")

        for identifier in ["onboarding.firstItems.name", "onboarding.firstItems.color"] {
            let field = app.textFields[identifier]
            field.scrollIntoView(in: app)
            XCTAssertTrue(field.exists, "\(identifier) is unreachable at AX5")
        }

        // Chips wrap rather than scrolling sideways, so the last category has
        // to be reachable by scrolling DOWN — a horizontal scroller would hide
        // it behind the gesture least likely to be found at this text size.
        let lastCategory = app.buttons["onboarding.firstItems.category.fragrance"]
        lastCategory.scrollIntoView(in: app)
        XCTAssertTrue(lastCategory.exists, "The last category chip cannot be reached at AX5")

        let add = app.buttons["onboarding.firstItems.add"]
        add.scrollIntoView(in: app)
        XCTAssertTrue(add.exists && add.isHittable, "Add to closet is unreachable at AX5")
        capture("58b-FirstItems-AX5-form")

        // The exit criterion, at the size where a footer is most likely to be
        // pushed off screen.
        let forward = app.buttons["onboarding.advance"]
        XCTAssertTrue(
            forward.exists && forward.isHittable && forward.isEnabled,
            "Skipping the first-items step is not possible at AX5"
        )
    }

    // MARK: - Scrolling helpers

    /// Scrolls down then back up looking for an element, asserting only that it
    /// EXISTS — a container with no tap action of its own never has to be
    /// hittable, and the question for one is whether the user can reach it.
    @discardableResult
    private func scrollUntilPresent(_ element: XCUIElement, maxSwipes: Int = 14) -> Bool {
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
