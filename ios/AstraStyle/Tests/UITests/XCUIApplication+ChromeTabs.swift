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
        let onBar = chromeTabBar.buttons[title]
        if onBar.waitForExistence(timeout: 2) {
            onBar.tap()
            return
        }
        let more = chromeTabBar.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: timeout), "\(title) tab missing and More is absent")
        more.tap()
        usleep(600_000)
        // iOS 26's More list surfaces extra tabs as cells, buttons, or
        // static texts depending on size class. Match the title loosely
        // enough to find "Profile" without grabbing an unrelated control
        // that merely contains the word.
        let extra = descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR identifier == %@ OR label BEGINSWITH[c] %@", title, title, title)
        ).firstMatch
        XCTAssertTrue(extra.waitForExistence(timeout: timeout), "\(title) not in the tab bar or More list")
        extra.tap()
    }
}
