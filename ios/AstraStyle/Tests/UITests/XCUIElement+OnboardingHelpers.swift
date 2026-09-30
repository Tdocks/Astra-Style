//
//  XCUIElement+OnboardingHelpers.swift
//  AstraStyleUITests
//

import XCTest

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
    func scrollIntoView(in app: XCUIApplication, maxSwipes: Int = 8) {
        var swipes = 0
        while !(exists && isHittable && centerIsInScrollViewport(in: app)) && swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        swipes = 0
        while !(exists && isHittable && centerIsInScrollViewport(in: app)) && swipes < maxSwipes {
            app.swipeDown(velocity: .slow)
            swipes += 1
        }
    }

    private func centerIsInScrollViewport(in app: XCUIApplication) -> Bool {
        let elementFrame = frame
        if identifier == "onboarding.advance" || identifier == "onboarding.back" {
            return true
        }
        let intersectingScrollViews = app.scrollViews.allElementsBoundByIndex
            .filter { $0.frame.intersects(elementFrame) }
        guard let scrollView = intersectingScrollViews.min(by: {
            ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
        }) else {
            return true
        }
        var viewport = scrollView.frame.insetBy(dx: 0, dy: 8)
        let forwardButton = app.buttons["onboarding.advance"]
        if forwardButton.exists {
            let footerFrame = forwardButton.frame
            if !footerFrame.equalTo(elementFrame) {
                viewport.size.height = max(0, min(viewport.maxY, footerFrame.minY) - viewport.minY)
            }
        }
        let center = CGPoint(x: elementFrame.midX, y: elementFrame.midY)
        // A non-onboarding screen has no `onboarding.advance` footer. Do not
        // query its frame unless `exists` was true — XCUITest treats a frame
        // read from a missing element as a failed query, which broke the
        // general Closet/Discover scroll helpers even though their target was
        // on screen.
        return viewport.contains(center)
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
