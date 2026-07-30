//
//  OnboardingFlowUITests.swift
//  AstraStyleUITests
//
//  Walks §6.3–§6.10 and captures every screen, so the whole flow can be
//  reviewed at once rather than one screen at a time.
//
//  These assert reachability and anchor content, not pixels. What they DO catch
//  is a step that stopped rendering, a Continue button that never enables, and
//  the §6.5 gate behaving wrongly in either direction — all of which are
//  invisible in unit tests because they live in the view layer.
//

import XCTest

/// `@MainActor` because every `XCUIApplication` member is main-actor isolated in
/// the iOS 26 SDK.
@MainActor
final class OnboardingFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 20

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            // Every run starts signed out with no saved draft. Without this the
            // flow inherits the previous run's progress and resumes mid-way,
            // which fails every assertion for the wrong reason.
            "-astra-reset-state"
        ]
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

    /// Enters guest mode, which reaches onboarding without a network or an
    /// account (spec §6.2) — so this runs on a clean simulator with no fixtures.
    private func enterOnboarding() {
        app.launch()
        let guest = app.buttons["Explore in guest mode"].exists
            ? app.buttons["Explore in guest mode"]
            : app.staticTexts["Explore in guest mode"]
        awaitElement(guest, "Welcome: guest entry")
        guest.tap()
    }

    // MARK: - The walk

    func testWalkTheWholeFlow() {
        enterOnboarding()

        // §6.3 — Kyra introduction.
        awaitElement(app.buttons["onboarding.begin"], "Intro: begin button")
        XCTAssertTrue(app.staticTexts["I'm Kyra."].exists, "Kyra's introduction is missing")
        capture("20-Onboarding-Intro")
        app.buttons["onboarding.begin"].tap()

        // §6.4 — Goals. Skippable, so Continue must already be enabled.
        awaitElement(app.buttons["onboarding.advance"], "Goals: advance button")
        XCTAssertTrue(
            app.buttons["onboarding.advance"].isEnabled,
            "Goals is skippable, so the forward button must be enabled with nothing selected"
        )
        capture("21-Onboarding-Goals")
        app.buttons["onboarding.goal.shop_more_intelligently"].tap()
        capture("22-Onboarding-Goals-Selected")
        app.buttons["onboarding.advance"].tap()

        // §6.5 — Identity. The ONLY required step: three picks plus a primary.
        awaitElement(app.buttons["onboarding.identity.quiet_luxury"], "Identity: cards")
        XCTAssertFalse(
            app.buttons["onboarding.advance"].isEnabled,
            "Identity must gate Continue until three are chosen and one is primary"
        )
        capture("23-Onboarding-Identity-Empty")

        app.buttons["onboarding.identity.quiet_luxury"].tap()
        app.buttons["onboarding.identity.modern_heritage"].tap()
        XCTAssertFalse(
            app.buttons["onboarding.advance"].isEnabled,
            "Two selections is not three — Continue must still be disabled"
        )

        app.buttons["onboarding.identity.minimalist"].tap()
        capture("24-Onboarding-Identity-Three")
        XCTAssertTrue(
            app.buttons["onboarding.advance"].isEnabled,
            "Three chosen with a defaulted primary should satisfy the gate"
        )

        // Re-nominate the primary explicitly, exercising the second stage.
        app.buttons["onboarding.primary.minimalist"].tap()
        capture("25-Onboarding-Identity-Primary")
        app.buttons["onboarding.advance"].tap()

        // §6.6 — Measurements.
        // A segmented `Picker` surfaces as a segmented control, not a button — the
        // first version of this query looked in `app.buttons` and never matched
        // even though the control was plainly on screen.
        awaitElement(
            app.textFields["onboarding.measurement.chest"],
            "Measurements: chest field"
        )
        capture("26-Onboarding-Measurements")

        let chest = app.textFields["onboarding.measurement.chest"]
        if chest.waitForExistence(timeout: 5) {
            chest.tap()
            chest.typeText("44")
        }
        // "Not sure" is a first-class answer (spec §6.6), not an empty field.
        app.buttons["onboarding.notSure.weight"].tap()
        capture("27-Onboarding-Measurements-Filled")
        app.buttons["onboarding.advance"].tap()

        // §6.7, §6.8, §6.9 are stubs — walk through them so the sequence and the
        // back/forward controls are exercised end to end.
        for (index, name) in ["28-Onboarding-Appearance",
                              "29-Onboarding-Lifestyle",
                              "30-Onboarding-Quiz"].enumerated() {
            awaitElement(app.buttons["onboarding.advance"], "Step after measurements #\(index)")
            usleep(400_000)
            capture(name)
            app.buttons["onboarding.advance"].tap()
        }

        // §6.10 — Result.
        awaitElement(app.buttons["onboarding.advance"], "Result: finish button")
        capture("31-Onboarding-Result")
    }

    /// Back must preserve what was entered. A flow that loses an answer when the
    /// user checks the previous screen is one he will not finish.
    func testBackPreservesAnswers() {
        enterOnboarding()
        awaitElement(app.buttons["onboarding.begin"], "Intro")
        app.buttons["onboarding.begin"].tap()

        awaitElement(app.buttons["onboarding.goal.find_signature_style"], "Goals")
        app.buttons["onboarding.goal.find_signature_style"].tap()
        app.buttons["onboarding.advance"].tap()

        awaitElement(app.buttons["onboarding.back"], "Identity: back button")
        app.buttons["onboarding.back"].tap()

        awaitElement(app.buttons["onboarding.goal.find_signature_style"], "Goals again")
        capture("32-Onboarding-Back-Preserved")
        // isSelected is the accessibility trait the row sets when chosen.
        XCTAssertTrue(
            app.buttons["onboarding.goal.find_signature_style"].isSelected,
            "Going back lost the selected goal"
        )
    }

    /// Spec §19 requires full Dynamic Type support, and the measurements screen
    /// is the densest in the app — a label, a field, a unit and a button on one
    /// row. It is where truncation shows up first.
    func testMeasurementsAtLargestDynamicType() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXL"]
        enterOnboarding()
        awaitElement(app.buttons["onboarding.begin"], "Intro at AX5")
        app.buttons["onboarding.begin"].tap()

        awaitElement(app.buttons["onboarding.advance"], "Goals at AX5")
        capture("33-Onboarding-Goals-AX5")
        app.buttons["onboarding.advance"].tap()


        // At AX5 each card is several times taller, so most of the grid starts
        // below the fold. XCUITest cannot tap a non-visible element, so each one
        // is scrolled to first — which is also what a real user has to do, and
        // therefore worth exercising.
        // Diagnostic: capture the identity screen at AX5 before touching it, so a
        // failure here is inspectable rather than just a timeout.
        usleep(600_000)
        capture("35-Onboarding-Identity-AX5-top")
        app.swipeUp()
        usleep(400_000)
        capture("36-Onboarding-Identity-AX5-scrolled")

        // Deliberately not in top-to-bottom order: executive is the 9th card and
        // minimalist the 4th, so reaching minimalist after executive requires
        // scrolling back UP — which a real user at AX5 does constantly, and which
        // a one-directional scroll helper silently cannot do.
        for identity in ["executive", "minimalist", "creative"] {
            selectIdentityCard(identity)
        }

        // Assert the gate is satisfied BEFORE tapping forward. Without this, a
        // tap that silently failed to select shows up as a timeout on the NEXT
        // screen, which reads like the next screen is broken — that is exactly
        // how one lost tap here cost a debugging session. The gate itself was
        // behaving correctly the whole time: it refused to advance on two
        // selections, which is what it is for.
        XCTAssertTrue(
            app.buttons["onboarding.advance"].isEnabled,
            "Three identities were tapped but the gate is still closed at AX5"
        )
        app.buttons["onboarding.advance"].tap()

        awaitElement(app.textFields["onboarding.measurement.chest"], "Measurements at AX5")
        capture("34-Onboarding-Measurements-AX5")
    }

    // MARK: - Selecting a card at accessibility sizes

    /// Scrolls a card into view and taps it, then verifies it actually became
    /// selected — retrying once if it did not.
    ///
    /// The retry is not defensive padding. iOS deliberately consumes the first
    /// tap on a scroll view that is still decelerating: that touch stops the
    /// scroll and is NOT forwarded to the subview underneath. `swipeUp()` is a
    /// flick with real velocity, and XCUITest's "wait for app to idle" returns
    /// while a SwiftUI ScrollView is still gliding — so a tap issued right after
    /// a swipe is silently eaten. It happened to exactly one of three cards, the
    /// selection count stopped at 2/3, the gate correctly refused to advance, and
    /// the failure surfaced 20 seconds later as "the measurements screen never
    /// appeared."
    ///
    /// So: scroll gently, wait for the frame to stop moving, tap, and confirm.
    private func selectIdentityCard(
        _ identity: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let card = app.buttons["onboarding.identity.\(identity)"]
        for _ in 1...2 {
            // Scroll BEFORE asserting existence. The grid is a `LazyVGrid`, so
            // cards outside the viewport are never instantiated (or are torn down
            // once scrolled far off) and are absent from the accessibility tree
            // entirely — not merely unhittable. Waiting for existence first
            // therefore times out on a card that would appear the moment the list
            // scrolled. (Not an app defect: VoiceOver scrolls the grid too, and
            // the cards materialise for it the same way.)
            card.scrollIntoView(in: app)
            guard card.exists else { continue }
            card.waitForStableFrame()
            guard card.isHittable else { continue }
            card.tap()
            if card.isSelected { return }
        }
        XCTFail(
            "Identity card never became selected at AX5: \(identity)",
            file: file, line: line
        )
    }
}

private extension XCUIElement {
    /// Swipes until this element both exists and can be tapped — searching
    /// downward first, then back upward.
    ///
    /// Checks `exists` as well as `isHittable` because lazy containers do not
    /// instantiate off-screen children at all — a `LazyVGrid` card outside the
    /// viewport is missing from the tree rather than present-but-hidden, so a
    /// helper that only polled `isHittable` would spin against an element that
    /// never materialised.
    ///
    /// Searches BOTH directions because "missing from the tree" gives no hint of
    /// where the element is. The first version only swiped up (scrolling down),
    /// and failed the moment a test tapped a card, scrolled on, and then needed a
    /// card above the viewport again: at AX5 the identity grid is one column and
    /// several screens tall, so after reaching the 9th card the 4th is far above
    /// the fold, torn down by the `LazyVGrid`, and unreachable by scrolling
    /// further down. The failure-time hierarchy dump showed the scroll bar at
    /// 100% with the sought card absent — ten swipes spent rubber-banding at the
    /// bottom while the target sat one screen up.
    ///
    /// Swipes at `.slow` velocity rather than the default flick. A fast swipe
    /// leaves the scroll view decelerating for well over a second after
    /// XCUITest considers the app idle, and iOS spends the next tap on stopping
    /// that deceleration instead of on the button underneath it.
    func scrollIntoView(in app: XCUIApplication, maxSwipes: Int = 10) {
        var swipes = 0
        while !(exists && isHittable) && swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        swipes = 0
        while !(exists && isHittable) && swipes < maxSwipes {
            app.swipeDown(velocity: .slow)
            swipes += 1
        }
    }

    /// Blocks until this element's frame stops changing between samples, so a tap
    /// is aimed at where the element will still be when the event lands.
    ///
    /// Returns as soon as two consecutive reads agree; gives up quietly at the
    /// timeout and lets the caller's own assertion report the problem, because a
    /// "frame never settled" failure would be less informative than the
    /// selection check that follows it.
    func waitForStableFrame(timeout: TimeInterval = 3) {
        var previous = CGRect.null
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard exists else { return }
            let current = frame
            if current == previous { return }
            previous = current
            usleep(150_000)
        }
    }
}
