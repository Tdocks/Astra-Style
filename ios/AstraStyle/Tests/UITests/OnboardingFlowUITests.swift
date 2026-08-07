//
//  OnboardingFlowUITests.swift
//  AstraStyleUITests
//
//  Walks §5.1 steps 6–13 (screens §6.3–§6.10, plus the two §5.1-only steps
//  between the quiz and the result) and captures every screen, so the whole
//  flow can be reviewed at once rather than one screen at a time.
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
    // `lazy` rather than an implicitly-unwrapped `XCUIApplication!`: the IUO
    // form is only there to bridge "declared in the class, assigned in setUp",
    // and it trades a compile-time guarantee for a runtime trap (CLAUDE.md:
    // no force unwraps). `lazy` gives the same "created once per test instance"
    // behaviour with no optionality at all, and defers construction to first
    // use — which happens from a @MainActor context, matching XCUIApplication's
    // own isolation in the iOS 26 SDK.
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

    /// Captures the current screen, then swipes down through the rest of the
    /// page capturing each screenful, stopping early once the view stops moving.
    ///
    /// Exists because a screenshot audit can only report on what it can see. The
    /// first review of these steps flagged seven required questions as "not found
    /// in any screenshot" — they were all present, just below the fold of the one
    /// capture taken. An audit that cannot see the screen produces findings about
    /// the capture rather than about the app.
    private func captureWholePage(prefix: String, screens: Int, includeFirst: Bool = true) {
        if includeFirst { capture(prefix) }

        var previous = app.screenshot().pngRepresentation
        for index in 1..<max(1, screens) {
            app.swipeUp(velocity: .slow)
            usleep(500_000)
            let current = app.screenshot().pngRepresentation
            // Identical frames mean the page has bottomed out and every further
            // shot would be a duplicate of the last one.
            if current == previous {
                capture("\(prefix)-END")
                return
            }
            previous = current
            capture("\(prefix)-\(index)")
        }
        // Hit the cap with the page still moving. Named so it is impossible to
        // mistake the last shot for the bottom of the page: three separate
        // review rounds reported content as "unreachable" when the truth was
        // that the capture stopped early, and each time the claim was only
        // plausible because nothing in the filenames said otherwise.
        capture("\(prefix)-TRUNCATED-more-below")
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

    /// Enters onboarding against the in-memory mocks.
    ///
    /// This used to tap "Explore in guest mode", which was the only
    /// account-free way in. ADR 0014 removed it, so the account-free entry
    /// is now `-astra-mock-backend` — Debug-only, swaps the whole dependency
    /// graph for `Core/Mocks`, and still runs on a clean simulator with no
    /// network and no fixtures.
    private func enterOnboarding() {
        app.launchArguments += ["-astra-mock-backend"]
        app.launch()
        awaitElement(app.buttons["onboarding.begin"], "Intro")
    }

    /// Every option tile currently on screen, whichever comparison it belongs to.
    ///
    /// Matched on the identifier prefix because the pair id is part of the
    /// identifier and the pairs are content. `onboarding.quiz.complete` and
    /// `onboarding.quiz.noPreference` share the `onboarding.quiz.` prefix, hence
    /// the more specific `.option.`.
    private var quizOptions: XCUIElementQuery {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "onboarding.quiz.option.")
        )
    }

    // MARK: - The walk

    /// The whole §6.3–§6.10 walk, in order. Each step is its own method so a
    /// failure names the screen it happened on, and so this reads as the
    /// sequence the spec describes rather than one 90-line script.
    func testWalkTheWholeFlow() {
        enterOnboarding()
        walkIntro()
        walkGoals()
        walkIdentity()
        walkMeasurements()
        walkAppearance()
        walkLifestyle()
        walkPreferenceQuiz()
        walkCaptureSteps()
        walkResult()
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

        // The far end of the grid is checked for REACHABILITY only, not tapped.
        // At AX5 the grid is one column and several screens tall, and a tap
        // issued at the bottom of it after a long scroll is eaten often enough to
        // make this test flaky — see `selectIdentityCard`. Reachability is the
        // part that is actually about accessibility; a reliable tap down there is
        // about XCUITest. Losing the tap does not lose the coverage.
        let lastCard = app.buttons["onboarding.identity.creative"]
        lastCard.scrollIntoView(in: app)
        XCTAssertTrue(
            lastCard.exists,
            "The last identity card cannot be reached by scrolling at AX5"
        )

        // Then select from the top of the grid, out of order — smart_casual is
        // third and modern_heritage first, so reaching modern_heritage afterwards
        // requires scrolling back UP, which is what a real user at AX5 does
        // constantly and what a one-directional scroll helper silently cannot do.
        // Short distances, because the subject of this test is the MEASUREMENTS
        // screen and the identity grid is only the gate in front of it.
        for identity in ["smart_casual", "modern_heritage", "quiet_luxury"] {
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

        // Carry on to the end at AX5, capturing each step. Every screen after
        // this one is skippable, so the walk needs no input — and the largest
        // text size is where these screens break first, so a shot of each one is
        // worth more than a shot of the two densest.
        for name in ["37-Onboarding-Appearance-AX5",
                     "38-Onboarding-Lifestyle-AX5",
                     "39-Onboarding-Quiz-AX5",
                     "40a-Onboarding-Reference-AX5",
                     "40b-Onboarding-FirstItems-AX5",
                     "40c-Onboarding-Result-AX5"] {
            let forward = app.buttons["onboarding.advance"]
            guard awaitElement(forward, "Forward button before \(name)") else { return }
            forward.waitForStableFrame()
            forward.tap()
            // Let the step render and settle before the shot, or the capture
            // catches a half-laid-out screen and the audit reads it as a defect.
            usleep(700_000)
            capture(name)

            // Keyed on what is on screen rather than on the capture's name, so
            // this follows §6.9 if the step order ever changes.
            if app.staticTexts["onboarding.quiz.progress"].exists {
                auditQuizAtAX5()
            }

            // At AX5 a step runs several screens tall, so a top-of-page capture
            // audits maybe a third of it. Walk down and back.
            // 12, not 5. At AX5 the lifestyle step runs far longer than five
            // screenfuls, and a cap that stops halfway produces an audit of the
            // capture rather than of the app — the first reviewer reasonably
            // read the last shot as the bottom of the page and reported
            // everything below it as unreachable. The loop exits early on a
            // repeated frame, so the cap only costs time on genuinely long
            // steps.
            captureWholePage(prefix: name, screens: 20, includeFirst: false)
            for _ in 0..<20 { app.swipeDown(velocity: .slow) }
            usleep(400_000)
        }
    }

    // MARK: - §6.10, signed in

    /// The Style DNA result with a real result on it: all six §6.10 sections,
    /// the honesty fields, and an edit that visibly changes what is shown.
    ///
    /// The last assertion is Phase 2's exit criterion stated as a user would
    /// state it — change your answer, regenerate, see a different result — and
    /// it is the one thing about this screen that a unit test can prove is
    /// wired and a UI test can prove is REACHABLE.
    func testStyleDNAResultShowsEverySectionAndRegenerates() {
        enterOnboardingSignedIn()
        walkToStyleDNAResult()

        let headline = app.staticTexts["onboarding.result.identity"]
        awaitElement(headline, "Result: primary style identity")
        let before = headline.label
        XCTAssertFalse(before.isEmpty, "The primary identity headline is empty")
        capture("41-Onboarding-Result-SignedIn")

        assertEverySectionIsReachable(context: "Signed in")
        captureWholePage(prefix: "41-Onboarding-Result-SignedIn", screens: 5, includeFirst: false)
        for _ in 0..<10 { app.swipeDown(velocity: .slow) }
        usleep(400_000)

        // Edit the input, not the prose. The sheet is §6.5 again, so the
        // controls are the ones the identity step already established.
        let edit = app.buttons["onboarding.result.edit"]
        edit.scrollIntoView(in: app)
        XCTAssertTrue(edit.exists && edit.isHittable, "The edit control is unreachable")
        edit.waitForStableFrame()
        edit.tap()

        awaitElement(app.buttons["onboarding.result.editor.confirm"], "Edit sheet")
        capture("41b-Onboarding-Result-Editing")

        // Nominate a different primary. The first pick defaulted to primary, so
        // this is a real change to the input the result is derived from.
        let newPrimary = app.buttons["onboarding.primary.quiet_luxury"]
        newPrimary.scrollIntoView(in: app)
        newPrimary.waitForStableFrame()
        newPrimary.tap()
        _ = newPrimary.waitUntilSelected()

        app.buttons["onboarding.result.editor.confirm"].tap()

        // Poll rather than read once: the regenerate is a round trip, and the
        // headline only changes after it returns.
        let deadline = Date().addingTimeInterval(timeout)
        var after = headline.label
        while after == before, Date() < deadline {
            usleep(200_000)
            after = headline.label
        }
        capture("41c-Onboarding-Result-Regenerated")
        XCTAssertNotEqual(
            after, before,
            "Regenerating after an edit left the result unchanged, so the user cannot tell it happened"
        )
    }

    /// Spec §19 at the largest text size, on the longest screen in the flow.
    ///
    /// Every other step was hardened at AX5; this one has more content than any
    /// of them — six sections, a wrapping palette, a card — and it is the only
    /// screen whose content length depends on what the server sent, so a layout
    /// that holds for a rich result can still strand a sparse one.
    func testStyleDNAResultAtLargestDynamicType() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXL"]
        enterOnboardingSignedIn()
        walkToStyleDNAResult()

        awaitElement(app.staticTexts["onboarding.result.identity"], "Result: identity at AX5")
        usleep(700_000)
        capture("42-Onboarding-Result-AX5")

        assertEverySectionIsReachable(context: "AX5")
        captureWholePage(prefix: "42-Onboarding-Result-AX5", screens: 20, includeFirst: false)

        // Back to the top, both to prove the page scrolls in both directions at
        // AX5 and because the controls below depend on being able to get there.
        for _ in 0..<25 { app.swipeDown(velocity: .slow) }
        usleep(400_000)
        XCTAssertTrue(
            scrollUntilPresent(app.staticTexts["onboarding.result.identity"]),
            "The identity headline cannot be reached again by scrolling back up at AX5"
        )

        // The two controls that must survive AX5: the edit affordance, and the
        // footer's Finish. A result the user can read but cannot act on or leave
        // is the failure mode this size produces.
        let edit = app.buttons["onboarding.result.edit"]
        edit.scrollIntoView(in: app)
        XCTAssertTrue(edit.exists && edit.isHittable, "The edit control is unreachable at AX5")

        let forward = app.buttons["onboarding.advance"]
        XCTAssertTrue(forward.exists && forward.isHittable, "Finish is unreachable at AX5")
    }

    // MARK: - §6.9 at the largest text size

    /// The quiz's own AX5 audit, run from inside the walk above.
    ///
    /// Two photographs side by side is the layout most likely to fail here — the
    /// images do not scale with Dynamic Type, so at AX5 they stay small while
    /// every label around them triples. The view answers that by going to one
    /// full-width column at `.accessibility1`, and what has to be true either way
    /// is that both outfits and the pass control can be reached and tapped.
    private func auditQuizAtAX5() {
        // Scroll BEFORE asserting. At AX5 a step runs several screens tall, and
        // an element below the fold of a lazily-populated container is absent
        // from the accessibility tree rather than present-but-unhittable — so a
        // bare `exists` check times out on something a swipe would reveal.
        let firstOption = quizOptions.element(boundBy: 0)
        firstOption.scrollIntoView(in: app)
        XCTAssertTrue(firstOption.exists, "The first outfit cannot be reached at AX5")

        let pass = app.buttons["onboarding.quiz.noPreference"]
        pass.scrollIntoView(in: app)
        XCTAssertTrue(
            pass.exists && pass.isHittable,
            "\"No preference\" is unreachable at AX5, which forces a coin flip"
        )
        capture("39b-Onboarding-Quiz-AX5-controls")

        // Answer one so the audit also covers the state after a choice, where the
        // undo control appears and the footer's label changes.
        let option = quizOptions.element(boundBy: 0)
        option.scrollIntoView(in: app)
        if option.exists, option.isHittable {
            option.waitForStableFrame()
            option.tap()
            usleep(500_000)
            capture("39c-Onboarding-Quiz-AX5-answered")
        }
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
            // Poll rather than read once. The first version read `isSelected`
            // immediately after `tap()`, got `false` because the accessibility
            // trait had not propagated yet (0.35s was not enough), retried, and
            // the retry TOGGLED THE CARD BACK OFF — so the guard against a lost
            // tap became a way to lose one.
            if card.waitUntilSelected() { return }
        }
        XCTFail(
            "Identity card never became selected at AX5: \(identity)",
            file: file, line: line
        )
    }
}

// Internal rather than `private`, which is file-scoped: these three helpers
// are the accumulated answer to how XCUITest actually behaves against a
// SwiftUI ScrollView at accessibility text sizes, and every one of them was
// written after a failure that looked like an app bug and was not.
// `OnboardingCaptureStepsUITests` needs the same three, and a second copy
// there would be a second place for that knowledge to rot.
extension XCUIElement {
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
    /// Polls until this element reports the `isSelected` trait.
    ///
    /// Necessary because `tap()` returns as soon as the event is synthesised,
    /// while the trait only appears once SwiftUI has re-rendered and the
    /// accessibility tree has been rebuilt. Reading the trait once, straight
    /// after the tap, reads the state from before it.
    func waitUntilSelected(timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isSelected { return true }
            usleep(150_000)
        }
        return false
    }

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

// MARK: - The walk, step by step

/// The per-screen halves of `testWalkTheWholeFlow`. In an extension purely so
/// the test class itself stays a readable list of what is being tested rather
/// than 300 lines of tapping.
private extension OnboardingFlowUITests {

    // MARK: Reaching §6.10 with a real result on it

    /// Enters onboarding as a SIGNED-IN user, against the in-memory mocks.
    ///
    /// Kept as a named alias of `enterOnboarding()`. Both entries used to
    /// differ — one guest, one signed in — and every §6.10 assertion below
    /// says which it meant. They are the same thing now (ADR 0014).
    private func enterOnboardingSignedIn() {
        enterOnboarding()
    }

    /// Walks §6.3-§6.9 with the minimum input the flow requires, to reach
    /// §6.10. Only the identity step is answered, because only it is required.
    private func walkToStyleDNAResult() {
        app.buttons["onboarding.begin"].tap()

        awaitElement(app.buttons["onboarding.advance"], "Goals")
        app.buttons["onboarding.advance"].tap()

        awaitElement(app.buttons["onboarding.identity.quiet_luxury"], "Identity")

        // Walk to the far end of the grid and back before tapping anything.
        //
        // This is not padding. Tapping the second card straight after the step
        // appeared failed every time at AX5 — the tap synthesised, the card
        // never took the `isSelected` trait, and the §6.5 gate stayed shut. At
        // that text size the grid is one column and several screens tall, so a
        // card whose top edge is on screen can have its CENTRE — where
        // XCUITest aims — under the footer or below the fold, and the tap lands
        // on the chrome instead. Scrolling to the end first means
        // `selectIdentityCard` reaches each card by scrolling back up to it,
        // which puts it in the middle of the viewport before it is tapped.
        // `testMeasurementsAtLargestDynamicType` does the same thing for the
        // same reason, and this is where that sequence came from.
        usleep(600_000)
        app.swipeUp()
        usleep(400_000)
        app.buttons["onboarding.identity.creative"].scrollIntoView(in: app)

        for identity in ["smart_casual", "modern_heritage", "quiet_luxury"] {
            selectIdentityCard(identity)
        }
        XCTAssertTrue(
            app.buttons["onboarding.advance"].isEnabled,
            "Three identities were tapped but the §6.5 gate is still closed"
        )
        app.buttons["onboarding.advance"].tap()

        // Everything between identity and the result is skippable.
        for step in ["measurements", "appearance", "lifestyle", "quiz", "reference", "firstItems"] {
            let forward = app.buttons["onboarding.advance"]
            guard awaitElement(forward, "Forward button on \(step)") else { return }
            forward.waitForStableFrame()
            forward.tap()
            usleep(400_000)
        }
    }

    /// A §6.10 section container, matched on any element type.
    ///
    /// `descendants(matching: .any)` rather than `app.otherElements[...]`
    /// because a view carrying `.accessibilityElement(children: .contain)`
    /// surfaces as whatever type XCUITest infers from its contents, and that is
    /// not stable across sections — the palette resolves differently from the
    /// signature list. Matching on the identifier alone is what the test
    /// actually means.
    private func resultSection(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Scrolls down then back up looking for an element, asserting only that it
    /// EXISTS.
    ///
    /// Separate from `scrollIntoView` because that helper also waits for
    /// `isHittable`, which a container element with no tap action of its own
    /// never has to be — the question for a section is whether the user can
    /// reach it, not whether he can tap it.
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

    /// The six §6.10 sections plus the honesty block, asserted as reachable.
    ///
    /// Secondary influences and the palette are checked from the same list as
    /// the rest deliberately: the point of the assertion is that every bullet
    /// spec §6.10 lists has somewhere on screen to be, and a section quietly
    /// dropped during a refactor is invisible to every other test in this file.
    private func assertEverySectionIsReachable(context: String) {
        let sections = [
            "onboarding.result.influences",
            "onboarding.result.palette",
            "onboarding.result.silhouette",
            "onboarding.result.signatures",
            "onboarding.result.priorities",
            "onboarding.result.knownInputs",
            "onboarding.result.openQuestions"
        ]
        for identifier in sections {
            XCTAssertTrue(
                scrollUntilPresent(resultSection(identifier)),
                "\(context): §6.10 section not reachable by scrolling — \(identifier)"
            )
        }
    }

    private func walkIntro() {
        // §6.3 — Kyra introduction.
        awaitElement(app.buttons["onboarding.begin"], "Intro: begin button")
        XCTAssertTrue(app.staticTexts["I'm Kyra."].exists, "Kyra's introduction is missing")
        capture("20-Onboarding-Intro")
        app.buttons["onboarding.begin"].tap()
    }

    private func walkGoals() {
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
    }

    private func walkIdentity() {
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
    }

    private func walkMeasurements() {
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
    }

    private func walkAppearance() {
        // §6.7 — Appearance. Captured WITH selections and in two scroll
        // positions. A screenshot of an untouched screen cannot show whether the
        // selected state is distinguishable from the unselected one, and a
        // single top-of-page shot leaves the questions below the fold unaudited
        // — both were real gaps found when these captures were reviewed.
        awaitElement(app.buttons["onboarding.appearance.skinUndertone.warm"], "Appearance: chips")
        app.buttons["onboarding.appearance.skinUndertone.warm"].tap()
        app.buttons["onboarding.appearance.hairColor.dark_brown"].tap()
        usleep(400_000)
        capture("28-Onboarding-Appearance")
        app.swipeUp(velocity: .slow)
        usleep(500_000)
        capture("28b-Onboarding-Appearance-Lower")
        app.buttons["onboarding.advance"].tap()
    }

    private func walkLifestyle() {
        // §6.8 — Lifestyle. Eleven fields, so one top-of-page shot audits a
        // fraction of the screen: the first review of it could not find seven of
        // the eleven required questions in any capture, and had to report them as
        // possibly missing. Walk the whole page instead.
        awaitElement(app.buttons["onboarding.advance"], "Lifestyle")
        usleep(400_000)
        captureWholePage(prefix: "29-Onboarding-Lifestyle", screens: 6)
        app.buttons["onboarding.advance"].tap()
    }

    private func walkPreferenceQuiz() {
        // §6.9 — the paired-image quiz.
        awaitElement(app.staticTexts["onboarding.quiz.progress"], "Quiz: progress line")
        usleep(400_000)
        capture("30-Onboarding-Quiz")

        // The forward button must NOT read "Continue" while comparisons are
        // waiting. Choosing an outfit is what advances the quiz, so a footer
        // button that looks like the control the user has been tapping and
        // instead leaves the step is the specific trap this asserts against.
        XCTAssertNotEqual(
            app.buttons["onboarding.advance"].label, "Continue",
            "The forward button claims to continue while comparisons are unanswered"
        )

        // Queried by identifier prefix rather than by pair id. The comparison set
        // is content — a test naming "formality-01" would fail the day someone
        // adds the texture pairs, which is exactly the change this feature was
        // shaped to make painless.
        XCTAssertEqual(quizOptions.count, 2, "A comparison must offer exactly two outfits")
        quizOptions.element(boundBy: 0).tap()

        awaitElement(app.buttons["onboarding.quiz.undo"], "Quiz: undo after a choice")
        capture("30b-Onboarding-Quiz-Answered")

        // Undo must take the choice back rather than being decorative.
        app.buttons["onboarding.quiz.undo"].tap()
        usleep(400_000)
        XCTAssertFalse(
            app.buttons["onboarding.quiz.undo"].exists,
            "Undo did not remove the only answer"
        )

        // Answer every comparison. Content-agnostic: keep choosing while a
        // comparison is on screen. "No preference" is exercised on the second one
        // — it is a first-class answer, not an escape hatch, and it has to advance
        // the quiz like any other.
        var answered = 0
        while quizOptions.count == 2, answered < 40 {
            if answered == 1 {
                app.buttons["onboarding.quiz.noPreference"].tap()
            } else {
                quizOptions.element(boundBy: 0).tap()
            }
            answered += 1
            usleep(300_000)
        }
        XCTAssertGreaterThan(answered, 0, "The quiz never presented a comparison")

        awaitElement(app.staticTexts["onboarding.quiz.complete"], "Quiz: completion card")
        capture("30c-Onboarding-Quiz-Complete")
        XCTAssertEqual(
            app.buttons["onboarding.advance"].label, "Continue",
            "With every comparison answered the forward button should offer to continue"
        )
        app.buttons["onboarding.advance"].tap()
    }

    /// §5.1 steps 11 and 12, passed through without answering either.
    ///
    /// Deliberately shallow. Both steps have their own suite —
    /// `OnboardingCaptureStepsUITests` — because the §29 consent gate and the
    /// closet cap need more assertions than a pass-through walk should carry.
    /// What this covers is the part only the full walk can: that neither step
    /// interrupts the sequence, and that both are captured in the same
    /// review pass as every other screen.
    private func walkCaptureSteps() {
        awaitElement(app.buttons["onboarding.advance"], "Reference photo step")
        usleep(400_000)
        capture("30d-Onboarding-Reference")
        XCTAssertTrue(
            app.buttons["onboarding.advance"].isEnabled,
            "The reference photo step is optional but its forward button is disabled"
        )
        app.buttons["onboarding.advance"].tap()

        awaitElement(app.buttons["onboarding.firstItems.add"], "First closet items step")
        usleep(400_000)
        capture("30e-Onboarding-FirstItems")
        XCTAssertTrue(
            app.buttons["onboarding.advance"].isEnabled,
            "The first-items step is optional but its forward button is disabled"
        )
        app.buttons["onboarding.advance"].tap()
    }

    private func walkResult() {
        // §6.10 — Result. What must be true is that he lands on something
        // coherent — not a spinner that never resolves and not an error — and
        // that the step's own promise ("edit anything that's wrong") is still
        // keepable.
        awaitElement(app.buttons["onboarding.advance"], "Result: finish button")
        capture("31-Onboarding-Result")

        XCTAssertFalse(
            app.staticTexts["onboarding.result.loading"].exists,
            "The result step is still spinning after generation should have resolved"
        )
        XCTAssertFalse(
            app.buttons["onboarding.result.retry"].exists,
            "The result step is showing a failure against the in-memory mocks"
        )
        let edit = app.buttons["onboarding.result.edit"]
        edit.scrollIntoView(in: app)
        XCTAssertTrue(edit.exists, "The result step cannot edit the answers it says it can edit")
        for _ in 0..<6 { app.swipeDown(velocity: .slow) }
        usleep(300_000)

        // Finishing must actually leave the flow. This is the one assertion in
        // the suite that covers the §6.10-to-§4 handover, and it is here rather
        // than in `ScreenQAUITests` on purpose: that file used to reach the tab
        // shell by walking onboarding, which made every onboarding change break
        // a tab-navigation test. It now enters through `-astra-skip-onboarding`,
        // so the real transition needs proving exactly once, by the test that
        // owns the flow.
        app.buttons["onboarding.advance"].tap()
        awaitElement(app.tabBars.firstMatch, "Main tab bar after finishing onboarding")
        capture("31b-Onboarding-Finished-MainShell")
    }
}
