//
//  XCUIApplication+ChromeTabs.swift
//  AstraStyleUITests
//
//  Chrome is the system tab bar. A sixth destination lives under More.
//

import XCTest

extension XCUIApplication {
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
        if tabItem.waitForExistence(timeout: 2) {
            tabItem.tap()
            return
        }

        let onBar = chromeTabBar.buttons[title]
        if onBar.waitForExistence(timeout: 2) {
            onBar.tap()
            return
        }
        let globalBarButton = tabBars.buttons[title]
        if globalBarButton.waitForExistence(timeout: 1) {
            globalBarButton.tap()
            return
        }

        let more = chromeTabBar.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: timeout), "\(title) tab missing and More is absent")
        more.tap()

        let liveRun = ProcessInfo.processInfo.environment["CI"] != nil
            || !ProcessInfo.processInfo.arguments.contains("-astra-mock-backend")
        usleep(liveRun ? 1_200_000 : 600_000)

        // More sheet items often live outside the tab bar hierarchy.
        let sheetButton = buttons[title]
        if sheetButton.waitForExistence(timeout: timeout) {
            sheetButton.tap()
            return
        }

        let tableCell = tables.cells.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH[c] %@", title, title)).firstMatch
        if tableCell.waitForExistence(timeout: timeout) {
            tableCell.tap()
            return
        }

        let collectionCell = collectionViews.cells.matching(
            NSPredicate(format: "label == %@ OR label BEGINSWITH[c] %@", title, title)
        ).firstMatch
        if collectionCell.waitForExistence(timeout: 2) {
            collectionCell.tap()
            return
        }

        // Scroll any sheet content, then retry once.
        for _ in 0..<4 {
            swipeUp(velocity: .slow)
            usleep(250_000)
            if buttons[title].waitForExistence(timeout: 1) {
                buttons[title].tap()
                return
            }
            let cell = tables.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
            if cell.waitForExistence(timeout: 1) {
                cell.tap()
                return
            }
        }

        let extra = descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR identifier == %@ OR label BEGINSWITH[c] %@", title, title, title)
        ).firstMatch
        XCTAssertTrue(extra.waitForExistence(timeout: timeout), "\(title) not in the tab bar or More list")
        extra.tap()
    }
}
