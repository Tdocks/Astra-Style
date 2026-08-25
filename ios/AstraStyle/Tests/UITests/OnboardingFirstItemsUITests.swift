//
//  OnboardingFirstItemsUITests.swift
//  AstraStyleUITests
//
//  §5.1 step 12 — "add first closet items, or skip".
//
//  THE PROPERTY UNDER TEST IS "CAN HE GET PAST IT". Phase 2's last exit
//  criterion is that skipping this step still reaches Home, and its failure
//  would not look like a bug on the screen where it happened — it would look
//  like a man stuck one screen short of the thing the whole flow exists to
//  show him. Everything else here is about which of the two ways in the step
//  offers FIRST, which is what `P2-ONBOARD-13` changed.
//
//  NOTHING HERE OPENS THE SCANNER. The sheet behind the photo control is the
//  camera, and a simulator has none; the scanner's own degradation to a Photos
//  import belongs to `P3-SCAN-*`, and driving the out-of-process picker from
//  here would make these tests about permission alerts. What is asserted is
//  that the control is present, enabled, and first.
//

import XCTest

// Main-actor isolation is inherited from the base class.
final class OnboardingFirstItemsUITests: OnboardingCaptureUITestCase {

    /// The photo path is the recommended way through this step, so its control
    /// has to be the first thing on the screen — not something found by
    /// scrolling past a form that exists for the case where the garment is not
    /// in the room.
    func testFirstItemsOffersThePhotoPathFirst() {
        walkToReferenceStep()
        leaveReferenceStep()

        let scan = app.buttons["onboarding.firstItems.scan"]
        awaitElement(scan, "First items: scan button")
        XCTAssertTrue(
            scan.isHittable,
            "The photo control needs scrolling to reach, so the typed form is what the step appears to be"
        )
        XCTAssertTrue(scan.isEnabled, "The photo control is present but cannot be used")
        capture("53d-FirstItems-PhotoPath")

        // Both ways in, on one screen. The typed form is not a fallback for a
        // missing camera — it is for a garment that is not in the room.
        XCTAssertTrue(
            scrollUntilPresent(anyElement("onboarding.firstItems.add")),
            "The typed form disappeared when the photo path arrived"
        )
    }

    func testAddingAFirstItem() {
        walkToReferenceStep()
        leaveReferenceStep()

        awaitElement(app.buttons["onboarding.firstItems.scan"], "First items: scan button")
        app.buttons["onboarding.firstItems.add"].scrollIntoView(in: app)
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
        awaitElement(app.chromeTabBar, "Home after skipping both capture steps")
        capture("57-SkippedBothSteps-Home")
    }

    /// Spec §19 on the longest screen in the flow at the largest text size:
    /// a photo control and its explanation, then a title, three labelled
    /// fields, seven category chips and a button.
    ///
    /// The photo path made this screen longer, which is exactly why it is
    /// checked here — the risk is that the step silently reverts to being a
    /// form with a camera button somewhere after it.
    func testFirstItemsAtLargestDynamicType() {
        walkToReferenceStep(largestTextSize: true)
        leaveReferenceStep()

        let scan = app.buttons["onboarding.firstItems.scan"]
        awaitElement(scan, "First items at AX5")
        usleep(700_000)
        capture("58-FirstItems-AX5")

        // ORDER, NOT "NO SCROLLING". At AX5 a headline and two sentences fill
        // the screen on their own, and nothing in this flow fits unscrolled at
        // this size — the reference step's own AX5 test scrolls its consent
        // control into view for the same reason. Demanding otherwise here
        // would be a standard no screen in the app meets, and the only way to
        // meet it would be to delete the explanation that makes a man willing
        // to let a machine read his jacket.
        //
        // What must survive AX5 is which path the step offers FIRST: the photo
        // control above the typed form in reading order, not below three text
        // fields and seven chips.
        let add = app.buttons["onboarding.firstItems.add"]
        XCTAssertTrue(add.exists, "The add button is unreachable at AX5")
        XCTAssertLessThan(
            scan.frame.minY, add.frame.minY,
            "At AX5 the typed form comes before the photo path, so the step reads as a form"
        )
        XCTAssertTrue(scan.isEnabled, "The photo control is present but cannot be used at AX5")
        scan.scrollIntoView(in: app)
        XCTAssertTrue(scan.isHittable, "The photo control cannot be reached by scrolling at AX5")

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
}
