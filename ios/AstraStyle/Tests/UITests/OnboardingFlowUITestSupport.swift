//
//  OnboardingGoalsUITestSupport.swift
//  AstraStyleUITests
//
//  Keeps the required §6.4 gate walk out of the already large onboarding-flow
//  audit while sharing its real accessibility controls and screenshot labels.
//

import XCTest

/// Captures the current screen and successive screenfuls until scrolling stops
/// or the safety cap is reached. Tests use the labels to keep an incomplete
/// capture distinct from a confirmed page bottom.
@MainActor
func captureOnboardingPage(
    app: XCUIApplication,
    prefix: String,
    screens: Int,
    includeFirst: Bool,
    capture: (String) -> Void
) {
    if includeFirst { capture(prefix) }

    var previous = app.screenshot().pngRepresentation
    for index in 1..<max(1, screens) {
        app.swipeUp(velocity: .slow)
        usleep(500_000)
        let current = app.screenshot().pngRepresentation
        if current == previous {
            capture("\(prefix)-END")
            return
        }
        previous = current
        capture("\(prefix)-\(index)")
    }
    capture("\(prefix)-TRUNCATED-more-below")
}

@MainActor
extension OnboardingFlowUITests {
    func walkIntro(capture: (String) -> Void) -> Bool {
        let timeout: TimeInterval = ProcessInfo.processInfo.environment["CI"] == nil ? 20 : 60
        let begin = app.buttons["onboarding.begin"]
        guard begin.waitForExistence(timeout: timeout) else {
            XCTFail("Intro: begin button never appeared")
            return false
        }
        guard app.staticTexts["I'm Kyra."].exists else {
            XCTFail("Kyra's introduction is missing")
            return false
        }
        capture("20-Onboarding-Intro")
        begin.tap()
        return true
    }

    func advancePastRequiredGoals(
        capture: (String) -> Void,
        beforeCapture: String,
        afterCapture: String,
        context: String = ""
    ) -> Bool {
        let timeout: TimeInterval = ProcessInfo.processInfo.environment["CI"] == nil ? 20 : 60
        let advance = app.buttons["onboarding.advance"]
        guard advance.waitForExistence(timeout: timeout) else {
            XCTFail("Goals: advance button never appeared\(context)")
            return false
        }
        guard !advance.isEnabled else {
            XCTFail("Goals must keep Continue disabled until a goal is selected\(context)")
            return false
        }
        capture(beforeCapture)

        let goal = app.buttons["onboarding.goal.shop_more_intelligently"]
        guard goal.waitForExistence(timeout: timeout) else {
            XCTFail("Goals: shopping goal never appeared\(context)")
            return false
        }
        goal.tap()
        guard goal.waitUntilSelected() else {
            XCTFail("Selecting a style goal did not register\(context)")
            return false
        }
        guard advance.isEnabled else {
            XCTFail("Selecting a style goal did not open Continue\(context)")
            return false
        }
        capture(afterCapture)
        advance.tap()
        return true
    }
}
