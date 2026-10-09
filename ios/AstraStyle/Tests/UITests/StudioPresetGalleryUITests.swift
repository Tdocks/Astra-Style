import XCTest

@MainActor
final class StudioPresetGalleryUITests: XCTestCase {
    private let app = XCUIApplication()

    func testPresetGalleryAppliesARealPresetWithoutShowingFakeResults() {
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-astra-reset-state",
            "-astra-mock-backend",
            "-astra-skip-onboarding"
        ]
        app.launch()
        XCTAssertTrue(app.chromeTabBar.waitForExistence(timeout: 20))

        let visualize = app.buttons["home.seeOnYou"]
        visualize.scrollIntoView(in: app)
        XCTAssertTrue(visualize.waitForExistence(timeout: 20))
        visualize.tap()

        let consent = app.buttons["studio.consent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 20))
        consent.tap()

        let controls = app.descendants(matching: .any)
            .matching(identifier: "studio.generationControls").firstMatch
        controls.scrollIntoView(in: app)
        XCTAssertTrue(controls.waitForExistence(timeout: 20))
        controls.tap()

        let browse = app.buttons["studio.presets.browse"]
        browse.scrollIntoView(in: app)
        XCTAssertTrue(browse.waitForExistence(timeout: 20))
        browse.tap()

        XCTAssertTrue(
            app.staticTexts["Schematic control preview · not a generated image"]
                .waitForExistence(timeout: 20)
        )
        let vacation = app.buttons["studio.presets.vacation"]
        vacation.scrollIntoView(in: app)
        XCTAssertTrue(vacation.waitForExistence(timeout: 20))
        vacation.tap()

        XCTAssertTrue(browse.waitForExistence(timeout: 20))
        browse.tap()
        let selectedVacation = app.buttons["studio.presets.vacation"]
        XCTAssertTrue(selectedVacation.waitForExistence(timeout: 20))
        XCTAssertTrue(selectedVacation.label.contains("Selected"))
    }
}
