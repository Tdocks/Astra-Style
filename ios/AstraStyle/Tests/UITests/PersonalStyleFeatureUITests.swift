import XCTest

@MainActor
final class PersonalStyleFeatureUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private let timeout: TimeInterval = ProcessInfo.processInfo.environment["CI"] == nil ? 20 : 60

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments += [
            "-UITestMode", "1",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryLarge"
        ]
    }

    @discardableResult
    private func awaitElement(
        _ element: XCUIElement,
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let found = element.waitForExistence(timeout: timeout)
        if !found {
            XCTFail("Never appeared: \(description)", file: file, line: line)
        }
        return found
    }

    /// Home's inspiration action opens a contextual Kyra conversation.
    func testHomeStyleInspiration() throws {
        launchMockMain()

        let inspiration = app.buttons["home.style.inspiration"]
        inspiration.scrollIntoView(in: app)
        awaitElement(inspiration, "Home style inspiration action")
        inspiration.tap()

        let userMessage = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "kyra.message.user",
                "Create a style inspiration"
            )
        ).firstMatch
        awaitElement(userMessage, "Today's inspiration request in the conversation")
        awaitElement(
            app.descendants(matching: .any)["kyra.message.assistant"].firstMatch,
            "Kyra's inspiration response"
        )
        awaitElement(
            app.descendants(matching: .any)["kyra.card.outfit"].firstMatch,
            "Structured outfit recommendation"
        )
    }

    /// The second Home path explicitly tells Kyra to use only owned pieces.
    func testHomeClosetBasedOutfit() throws {
        launchMockMain()

        let closetOutfit = app.buttons["home.style.fromCloset"]
        closetOutfit.scrollIntoView(in: app)
        awaitElement(closetOutfit, "Home closet outfit action")
        closetOutfit.tap()

        let userMessage = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "kyra.message.user",
                "using only pieces in my closet"
            )
        ).firstMatch
        awaitElement(userMessage, "Closet-only outfit request in the conversation")
        awaitElement(
            app.descendants(matching: .any)["kyra.card.outfit"].firstMatch,
            "Outfit card built from closet pieces"
        )
    }

    /// Monthly Review reads real mock repository records and sends those facts
    /// into a contextual Kyra conversation.
    func testMonthlyReviewAndKyraReflection() throws {
        launchMockMain()

        let reviewCard = app.descendants(matching: .any)["home.monthlyReview"]
        reviewCard.scrollIntoView(in: app)
        awaitElement(reviewCard, "Monthly Review entry on Home")
        reviewCard.tap()

        awaitElement(app.navigationBars["Monthly Review"], "Monthly Review screen")
        awaitElement(app.staticTexts["New pieces"], "Monthly Review item count")
        awaitElement(app.staticTexts["Looks worn"], "Monthly Review wear count")
        awaitElement(app.staticTexts["Your challenge"], "Monthly Review next-month challenge")
        awaitElement(
            app.descendants(matching: .any)["monthlyReview.versatility"],
            "Recorded month-over-month versatility change"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "increased by 4 points"))
                .firstMatch.waitForExistence(timeout: timeout),
            "Monthly Review should compare the seeded current score with its prior-month baseline"
        )

        let reflect = app.buttons["monthlyReview.askKyra"]
        reflect.scrollIntoView(in: app)
        awaitElement(reflect, "Talk this through with Kyra action")
        reflect.tap()

        awaitElement(
            app.descendants(matching: .any)["kyra.message.user"].firstMatch,
            "Monthly facts sent to Kyra"
        )
        awaitElement(
            app.descendants(matching: .any)["kyra.message.assistant"].firstMatch,
            "Kyra's monthly reflection"
        )
    }

    /// Outfit detail carries the selected outfit into chat so swap and
    /// formality questions can refine the look already on screen.
    func testOutfitSpecificKyraChat() throws {
        launchMockMain()
        app.chromeTab("Closet").tap()

        let grabLook = app.buttons["closet.looks.open"].firstMatch
        grabLook.scrollIntoView(in: app)
        awaitElement(grabLook, "Saved look action")
        grabLook.tap()

        let askKyra = app.buttons["outfitDetail.action.askKyra"]
        askKyra.scrollIntoView(in: app)
        awaitElement(askKyra, "Outfit-specific Kyra action")
        askKyra.tap()

        let userMessage = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "kyra.message.user",
                "swap the pants"
            )
        ).firstMatch
        awaitElement(userMessage, "Outfit adjustment question")
        awaitElement(
            app.descendants(matching: .any)["kyra.message.assistant"].firstMatch,
            "Kyra's outfit adjustment response"
        )
    }

    func testPackingReminderOptIn() throws {
        launchMockMain()
        app.tapChromeTab("Profile", timeout: timeout)

        let notificationsRow = app.descendants(matching: .any)["profile.notificationsRow"]
        awaitElement(notificationsRow, "Profile notifications settings")
        notificationsRow.tap()

        let loading = app.descendants(matching: .any)["profile.notifications.loading"]
        XCTAssertTrue(loading.waitForNonExistence(timeout: timeout), "Notification settings did not finish loading")

        let packingReminder = app.descendants(matching: .any)["profile.reminder.packingTrip"]
        awaitElement(packingReminder, "Packing reminder preference")
        XCTAssertEqual(packingReminder.value as? String, "0")
        XCTAssertTrue(packingReminder.isEnabled, "Packing reminder should be enabled after preferences load")
        packingReminder.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

        let enabled = NSPredicate(format: "value == %@", "1")
        expectation(for: enabled, evaluatedWith: packingReminder)
        waitForExpectations(timeout: timeout)
    }

    private func launchMockMain() {
        app.launchArguments += [
            "-astra-reset-state",
            "-astra-mock-backend",
            "-astra-skip-onboarding"
        ]
        app.launch()
        awaitElement(app.chromeTabBar, "Main tab bar under mock backend")
    }
}
