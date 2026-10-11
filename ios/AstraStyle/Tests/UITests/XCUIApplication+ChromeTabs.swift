//
//  XCUIApplication+ChromeTabs.swift
//  AstraStyleUITests
//
//  Chrome is the system tab bar. A sixth destination lives under More.
//

import XCTest

extension XCUIApplication {
    func waitForInspirationReady(generateButton: XCUIElement, timeout: TimeInterval) {
        let allowance = staticTexts["home.inspiration.allowance"]
        let allowanceLoaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "20 of 20"),
            object: allowance
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [allowanceLoaded], timeout: timeout),
            .completed,
            "Inspiration context did not finish loading"
        )
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: generateButton)
        XCTAssertEqual(
            XCTWaiter.wait(for: [enabled], timeout: timeout),
            .completed,
            "Generate action should be enabled: \(generateButton.debugDescription)"
        )
    }

    var chromeTabBar: XCUIElement {
        let tagged = descendants(matching: .any)["main.tabBar"]
        if tagged.exists { return tagged }
        return tabBars.firstMatch
    }

    func chromeTab(_ title: String) -> XCUIElement {
        let onBar = chromeTabBar.buttons[title]
        if onBar.exists { return onBar }
        return tabBars.buttons[title]
    }

    /// Taps a chrome destination, opening More when iOS has collapsed it.
    func tapChromeTab(_ title: String, timeout: TimeInterval = 8) {
        let tabID = title.lowercased()
        let tabItem = descendants(matching: .any)["main.tab.\(tabID)"].firstMatch
        if tabItem.waitForExistence(timeout: timeout) {
            tabItem.tap()
            return
        }

        let onBar = chromeTabBar.buttons[title]
        if onBar.waitForExistence(timeout: timeout) {
            onBar.tap()
            return
        }
        let globalBarButton = tabBars.buttons[title]
        if globalBarButton.exists {
            globalBarButton.tap()
            return
        }

        selectChromeTabFromMore(title, timeout: timeout)
    }

    private func selectChromeTabFromMore(_ title: String, timeout: TimeInterval) {
        let more = chromeTabBar.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: timeout), "\(title) tab missing and More is absent")
        more.tap()

        let destination = moreDestination(title)
        XCTAssertTrue(destination.waitForExistence(timeout: timeout), "\(title) not in the tab bar or More list")
        if !destination.isHittable {
            for _ in 0..<4 where !destination.isHittable {
                swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(destination.isHittable, "\(title) is present in More but not reachable")
        destination.tap()
    }

    private func moreDestination(_ title: String) -> XCUIElement {
        let exactLabelOrIdentifier = NSPredicate(format: "label == %@ OR identifier == %@", title, title)
        let buttonMatch = self.buttons.matching(exactLabelOrIdentifier).firstMatch
        if buttonMatch.exists { return buttonMatch }

        let tableCells = tables.cells.matching(exactLabelOrIdentifier).firstMatch
        if tableCells.exists { return tableCells }

        let collectionCells = collectionViews.cells.matching(exactLabelOrIdentifier).firstMatch
        if collectionCells.exists { return collectionCells }

        return descendants(matching: .any).matching(exactLabelOrIdentifier).firstMatch
    }
}
