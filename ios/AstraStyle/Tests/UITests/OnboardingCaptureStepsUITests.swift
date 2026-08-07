//
//  OnboardingCaptureStepsUITests.swift
//  AstraStyleUITests
//
//  §5.1 step 11 — the optional reference photo.
//
//  A suite of its own rather than more methods on `OnboardingFlowUITests`, for
//  two reasons. The obvious one is length: that file already walks eight
//  screens and hardens three of them at AX5. The better one is that this step
//  is tested for something different from the rest of the flow. Every other
//  step is checked for "does it render and can it be answered"; this one is
//  checked for "does the §29 gate hold", which is the property whose failure
//  would not look like a bug on the screen where it happened.
//
//  §5.1 step 12 used to live here too. It moved to
//  `OnboardingFirstItemsUITests` when the photo path (`P2-ONBOARD-13`) pushed
//  this class past SwiftLint's `type_body_length` limit; the shared walk to
//  both steps is now in `OnboardingCaptureUITestCase`, whose header explains
//  the split and what a simulator cannot cover.
//

import XCTest

final class OnboardingCaptureStepsUITests: OnboardingCaptureUITestCase {

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
}
