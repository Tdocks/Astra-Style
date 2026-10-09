//
//  PerformanceAcceptanceUITests.swift
//  AstraStyleUITests
//
//  Opt-in measurements for §20. Run on a supported physical device for device
//  acceptance; simulator values are diagnostic only. The mock flows use a
//  seeded cached brief and local photo files, with no provider/network calls.
//

import XCTest

@MainActor
final class PerformanceAcceptanceUITests: XCTestCase {
    func testColdLaunchToResponsiveHome() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-astra-mock-backend",
            "-astra-skip-onboarding",
            "-astra-measure-performance"
        ]

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(
            metrics: [
                XCTApplicationLaunchMetric(waitUntilResponsive: true),
                XCTOSSignpostMetric(
                    subsystem: "com.astrastyle.app",
                    category: "Performance",
                    name: "AppLaunchToInteractive"
                )
            ],
            options: options
        ) {
            app.launch()
            XCTAssertTrue(app.chromeTabBar.waitForExistence(timeout: 30))
            app.terminate()
        }
    }

    func testCachedHomeRender() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-astra-mock-backend",
            "-astra-skip-onboarding",
            "-astra-measure-performance"
        ]

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(
            metrics: [
                XCTOSSignpostMetric(
                    subsystem: "com.astrastyle.app",
                    category: "Performance",
                    name: "HomeCachedRender"
                )
            ],
            options: options
        ) {
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["home.look"].waitForExistence(timeout: 30))
            app.terminate()
        }
    }

    func testLargeClosetGridScrollHitchesAndMemory() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-astra-mock-backend",
            "-astra-skip-onboarding",
            "-astra-performance-closet"
        ]
        app.launch()
        XCTAssertTrue(app.chromeTabBar.waitForExistence(timeout: 30))
        app.tapChromeTab("Closet")

        let allItems = app.buttons["closet.category.all"]
        XCTAssertTrue(allItems.waitForExistence(timeout: 15))
        allItems.scrollIntoView(in: app)
        allItems.tap()
        let gridScroll = app.scrollViews.firstMatch
        XCTAssertTrue(gridScroll.waitForExistence(timeout: 10))

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        let scrollMetrics: [any XCTMetric]
        if #available(iOS 26.0, *) {
            scrollMetrics = [XCTHitchMetric(application: app), XCTMemoryMetric()]
        } else {
            // XCTest's hitch-count metric requires iOS 26. On earlier test
            // devices, capture the system scroll and deceleration duration;
            // this is diagnostic animation timing, not a hitch-count claim.
            scrollMetrics = [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTMemoryMetric()]
        }
        measure(metrics: scrollMetrics, options: options) {
            let newestTile = app.buttons["closet.grid.item.00000000-0000-4000-8000-00000000007d"]
            let oldestTile = app.buttons["closet.grid.item.00000000-0000-4000-8000-000000000001"]
            XCTAssertTrue(newestTile.isHittable, "The newest fixture tile should begin at the top.")

            var reachedOldestTile = oldestTile.isHittable
            for _ in 0..<45 where !reachedOldestTile {
                gridScroll.swipeUp(velocity: .fast)
                reachedOldestTile = oldestTile.isHittable
            }
            XCTAssertTrue(reachedOldestTile, "The scroll pass must reach the oldest of all 125 items.")

            var returnedToNewestTile = newestTile.isHittable
            for _ in 0..<45 where !returnedToNewestTile {
                gridScroll.swipeDown(velocity: .fast)
                returnedToNewestTile = newestTile.isHittable
            }
            XCTAssertTrue(returnedToNewestTile, "The reverse pass must return to the top of the grid.")
        }
        app.terminate()
    }
}
