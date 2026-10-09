import XCTest

@MainActor
final class StartupStoreRecoveryUITests: XCTestCase {
    func testPersistentStoreFailureOffersSafeRetry() throws {
        try recoverFromStoreFailure(lightAccessibility: false)
    }

    func testPersistentStoreFailureOffersSafeRetryLightAccessibility() throws {
        try recoverFromStoreFailure(lightAccessibility: true)
    }

    private func recoverFromStoreFailure(lightAccessibility: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestMode", "1",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-astra-reset-state",
            "-astra-mock-backend",
            "-astra-skip-onboarding",
            "-astra-test-store-open-failure-once"
        ]
        if lightAccessibility {
            app.launchArguments += [
                "-astra-theme", "light",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        }
        addUIInterruptionMonitor(withDescription: "Apple Account Verification") { alert in
            guard alert.label.contains("Apple Account Verification") else { return false }
            let notNow = alert.buttons["Not Now"]
            guard notNow.exists else { return false }
            notNow.tap()
            return true
        }
        app.launch()

        let title = app.staticTexts["Saved data unavailable"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "Persistent-store recovery screen did not appear")
        dismissAppleAccountVerificationIfPresent(app)
        XCTAssertTrue(app.staticTexts[
            "Astra Style couldn't open your saved data. Nothing was deleted. Check your device storage, then try again."
        ].exists)
        let retry = app.buttons["startup.store.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 20), "Retry action did not appear")
        XCTAssertEqual(retry.identifier, "startup.store.retry")
        XCTAssertTrue(retry.isHittable, "Retry should remain reachable at accessibility text sizes")
        let mainTabBar = app.descendants(matching: .any)["main.tabBar"]
        XCTAssertFalse(mainTabBar.exists, "The editable app root must stay unavailable while persistence is closed")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = lightAccessibility
            ? "Persistent store recovery light accessibility"
            : "Persistent store recovery"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        retry.tap()

        XCTAssertTrue(mainTabBar.waitForExistence(timeout: 20), "The app did not resume after retry")
        XCTAssertFalse(title.exists)
        XCTAssertFalse(retry.exists, "The recovery action should disappear after the app resumes")
    }

    private func dismissAppleAccountVerificationIfPresent(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let verificationAlert = springboard.alerts["Apple Account Verification"]
        guard verificationAlert.waitForExistence(timeout: 2) else { return }
        // A safe app-window tap activates the interruption monitor. If it
        // doesn't dismiss the prompt, tap only its explicit Not Now action.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.12)).tap()
        if verificationAlert.exists {
            let notNow = verificationAlert.buttons["Not Now"]
            XCTAssertTrue(notNow.exists, "Apple verification alert must offer Not Now")
            notNow.tap()
        }
        XCTAssertFalse(verificationAlert.exists, "Dismiss the verification alert before the screenshot")
    }
}
