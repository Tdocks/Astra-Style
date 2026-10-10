//
//  AstraStyleUITests.swift
//  AstraStyleUITests
//
//  Spec §22 "UI tests" — XCUITest (not Swift Testing; UI automation still
//  needs `XCTest`/`XCUIApplication` even in an otherwise Swift-Testing
//  codebase, per the build instructions).
//
//  Every spec §22 flow now runs against `-astra-mock-backend` and asserts
//  visible behavior. Live-provider contracts remain covered at repository /
//  Edge boundaries; UI automation owns reachability, state, and copy.
//

import XCTest

/// `@MainActor` for the same reason as `ScreenQAUITests`: XCUITest's element
/// APIs are main-actor isolated in the iOS 26 SDK.
@MainActor
final class AstraStyleUITests: XCTestCase {
    // `lazy` rather than an implicitly-unwrapped `XCUIApplication!`: the IUO
    // form is only there to bridge "declared in the class, assigned in setUp",
    // and it trades a compile-time guarantee for a runtime trap (CLAUDE.md:
    // no force unwraps). `lazy` gives the same "created once per test instance"
    // behaviour with no optionality at all, and defers construction to first
    // use — which happens from a @MainActor context, matching XCUIApplication's
    // own isolation in the iOS 26 SDK.
    private lazy var app = XCUIApplication()

    /// How long to wait for a screen to appear. Longer on CI — same rationale
    /// as `OnboardingFlowUITests`.
    private let timeout: TimeInterval = ProcessInfo.processInfo.environment["CI"] == nil ? 20 : 60

    // Async overrides inherit the class's @MainActor isolation; the throwing
    // synchronous ones do not (see ScreenQAUITests for the full note).
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

    /// Spec §22 "Complete onboarding". Owner: P2-ONBOARD.
    func testCompleteOnboarding() throws {
        app.launchArguments += [
            "-astra-reset-state",
            "-astra-mock-backend",
            "-astra-test-onboarding-state"
        ]
        app.launch()

        awaitElement(app.buttons["onboarding.begin"], "Onboarding intro")
        app.buttons["onboarding.begin"].tap()

        let graph = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Men's looks")
        ).firstMatch
        awaitElement(graph, "Wardrobe graph")
        graph.tap()
        app.buttons["onboarding.advance"].tap()

        for identity in ["quiet_luxury", "modern_heritage", "minimalist"] {
            let card = app.buttons["onboarding.identity.\(identity)"]
            card.scrollIntoView(in: app)
            card.waitForStableFrame()
            card.tap()
            XCTAssertTrue(card.waitUntilSelected(), "Identity did not select: \(identity)")
        }
        XCTAssertTrue(app.buttons["onboarding.advance"].isEnabled)
        app.buttons["onboarding.advance"].tap()

        // Quiz and first-items are both optional on the ADR 0015 front door.
        for step in ["quiz", "first items"] {
            let forward = app.buttons["onboarding.advance"]
            awaitElement(forward, "Forward button on \(step)")
            forward.tap()
            usleep(500_000)
        }

        let finish = app.buttons["onboarding.advance"]
        awaitElement(finish, "Style DNA finish")
        finish.tap()
        awaitElement(app.chromeTabBar, "Main tab bar after onboarding")
        awaitElement(app.descendants(matching: .any)["home.look"], "Daily Brief after onboarding")

        let completionProbe = app.descendants(matching: .any)["test.onboarding.completion"]
        awaitElement(completionProbe, "Mock onboarding completion acceptance state")
        assertOnboardingCompletionWasWritten(probe: completionProbe)
    }

    /// Spec §22 "Add a garment" / P3-TEST-02 — manual entry via ClosetItemForm.
    ///
    /// Runs against `-astra-mock-backend` (in-memory `MockClosetRepository`)
    /// plus `-astra-skip-onboarding` so the Closet tab is reachable without
    /// walking §6.3–§6.10. Asserts the saved name appears in the closet
    /// grid and that detail shows a wear count of 0.
    func testAddGarment() throws {
        launchMockCloset()
        let closetTitle = app.staticTexts["My Closet"].firstMatch
        awaitElement(closetTitle, "Closet root")

        let itemName = "UI Test Oxford \(Int(Date().timeIntervalSince1970))"
        submitManualGarment(named: itemName)

        // The sheet must be gone before we tap Tops — while it is up,
        // XCUITest can hit the form's Tops *chip* (`closet.form.category.top`)
        // instead of the closet category tile (that was the prior CI miss).
        let formHeader = app.descendants(matching: .any)["closet.form.header"]
        XCTAssertTrue(
            formHeader.waitForNonExistence(timeout: timeout),
            "Add-garment sheet did not dismiss after submit — save likely failed"
        )
        awaitElement(closetTitle, "Closet root after save")

        // LazyVGrid below category tiles is off-screen — open Tops instead.
        let topsTile = app.descendants(matching: .any)["closet.category.top"]
        awaitElement(topsTile, "Tops category tile after save")
        topsTile.tap()

        let newTile = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "closet.grid.item.",
                itemName
            )
        ).firstMatch
        XCTAssertTrue(
            newTile.waitForExistence(timeout: timeout),
            "Saved garment '\(itemName)' did not appear in the Tops grid"
        )
        assertZeroWearCount(forTile: newTile, itemName: itemName)
    }

    private func launchMockCloset() {
        app.launchArguments += [
            "-astra-mock-backend",
            "-astra-skip-onboarding"
        ]
        app.launch()
        awaitElement(app.chromeTabBar, "Main tab bar under mock backend")
        let closetTab = app.chromeTab("Closet")
        awaitElement(closetTab, "Closet tab")
        closetTab.tap()
    }

    private func submitManualGarment(named itemName: String) {
        let addButton = app.buttons["closet.header.addManually"]
        awaitElement(addButton, "Manual add button")
        addButton.tap()
        awaitElement(app.descendants(matching: .any)["closet.form.header"], "Add garment form")

        // Category first, while the keyboard is down — same lesson as
        // `OnboardingCaptureStepsUITests.testAddingAFirstItem`.
        let categoryChip = app.descendants(matching: .any)["closet.form.category.top"]
        awaitElement(categoryChip, "Tops category chip")
        categoryChip.tap()

        let nameField = app.descendants(matching: .any)["closet.form.name"]
        awaitElement(nameField, "Name field")
        nameField.scrollIntoView(in: app)
        nameField.waitForStableFrame()
        nameField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Name field did not open the keyboard")
        // Trailing newline resigns focus so the submit control is not
        // obscured by the keyboard when we tap it.
        nameField.typeText(itemName + "\n")

        let submit = app.descendants(matching: .any)["closet.form.submit"]
        awaitElement(submit, "Add garment submit")
        XCTAssertTrue(submit.isEnabled, "Submit should enable once name and category are set")
        submit.tap()
    }

    private func assertZeroWearCount(forTile newTile: XCUIElement, itemName: String) {
        newTile.tap()
        awaitElement(app.staticTexts[itemName].firstMatch, "Item detail name")
        let wornRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND value CONTAINS[c] %@", "Worn", "0 wear")
        ).firstMatch
        var swipes = 0
        while !wornRow.exists && swipes < 6 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(
            wornRow.waitForExistence(timeout: timeout),
            "Expected a wear count of 0 on the newly added garment"
        )
    }

    /// Spec §22 "Ask Kyra" / P5-TEST-02.
    ///
    /// Runs against `-astra-mock-backend` (`MockKyraRepository`, whose reply
    /// carries an outfit card citing `SampleData.heroOutfit`). This checks
    /// the native conversation UI deterministically; it does not establish
    /// live provider or staging acceptance, which requires separate signed-in
    /// requests against the deployed Kyra function.
    ///
    /// Asserts the two things the skip owed: a STRUCTURED response (an
    /// outfit card whose garments are the seeded closet's rows, not raw
    /// text) and at least one live suggested action.
    func testAskKyra() throws {
        app.launchArguments += [
            "-astra-mock-backend",
            "-astra-skip-onboarding"
        ]
        app.launch()
        awaitElement(app.chromeTabBar, "Main tab bar under mock backend")

        // The Ask Kyra global action floats above the tab bar on every tab.
        let askButton = app.descendants(matching: .any)["kyra.ask"]
        awaitElement(askButton, "Ask Kyra orb")
        askButton.tap()

        // A new conversation's empty state IS the suggested prompts;
        // tapping one must send it as a real message (P5-KYRA-15).
        let firstPrompt = app.buttons["What should I wear tonight?"]
        awaitElement(firstPrompt, "First suggested prompt")
        firstPrompt.tap()

        // The reply renders structured: Kyra's message text, an outfit
        // card, and a suggested action — not one blob of unformatted prose.
        awaitElement(
            app.descendants(matching: .any)["kyra.message.assistant"].firstMatch,
            "Kyra's reply message"
        )
        let outfitCard = app.descendants(matching: .any)["kyra.card.outfit"].firstMatch
        awaitElement(outfitCard, "Outfit card in Kyra's reply")

        // The card's item references resolve to the closet seeded for the
        // test user: the hero outfit's top is SampleData's Drake's "Knit
        // Polo", and the silhouette labels each slot with the garment name.
        let knitPolo = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Knit Polo")
        ).firstMatch
        XCTAssertTrue(
            knitPolo.waitForExistence(timeout: timeout),
            "Outfit card should render the seeded closet item 'Knit Polo'"
        )

        let suggestedAction = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "kyra.action.")
        ).firstMatch
        XCTAssertTrue(
            suggestedAction.waitForExistence(timeout: timeout),
            "Reply should surface at least one performable suggested action"
        )
    }

    func testKyraQueuedPreviewOpensAndReturnsToChat() throws {
        assertQueuedPreviewFlow()
    }

    func testKyraQueuedPreviewLightAccessibilityText() throws {
        assertQueuedPreviewFlow(extraArguments: [
            "-astra-theme", "light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
    }

    private func assertQueuedPreviewFlow(extraArguments: [String] = []) {
        launchMockMain(extraArguments: ["-astra-test-chat-preview"] + extraArguments)
        let ask = app.descendants(matching: .any)["kyra.ask"]
        awaitElement(ask, "Ask Kyra")
        ask.tap()
        let prompt = app.buttons["What should I wear tonight?"]
        awaitElement(prompt, "Styling prompt")
        prompt.tap()
        let preview = app.buttons["Open preview"]
        awaitElement(preview, "Queued preview action")
        preview.scrollIntoView(in: app)
        preview.tap()
        awaitElement(app.staticTexts["Visual estimate"], "Studio detail sheet")
        awaitElement(app.staticTexts["This is a visual estimate, not a photograph."], "Completed preview after status polling")
        let close = app.buttons["kyra.preview.close"]
        awaitElement(close, "Preview close button")
        close.tap()
        awaitElement(app.navigationBars["Kyra"], "Conversation after closing preview")
        XCTAssertTrue(preview.exists, "Closing the preview should retain its chat action")
    }

    /// Spec §22 "Open paywall and restore purchases". Owner: P7-SUB.
    func testOpenPaywallAndRestorePurchases() throws {
        launchMockMain(extraArguments: ["-astra-audit-paywall", "settingsUpgrade"])
        awaitElement(app.descendants(matching: .any)["paywall.hero"], "Paywall")
        let restore = app.descendants(matching: .any)["paywall.restore"]
        awaitElement(restore, "Restore Purchases")
        restore.tap()
        usleep(1_000_000)
        XCTAssertFalse(
            app.descendants(matching: .any)["paywall.error"].exists,
            "Restore Purchases ended in an error under the StoreKit test configuration"
        )
    }

    /// Spec §22 "Delete account". Owner: P7-SUB (flow) / P1-CORE (underlying `DELETE /account`).
    func testDeleteAccount() throws {
        launchMockMain()
        app.tapChromeTab("Profile")
        let privacy = app.descendants(matching: .any)["profile.privacyAndDataRow"]
        privacy.scrollIntoView(in: app)
        privacy.tap()
        let deleteRow = app.descendants(matching: .any)["privacyAndData.deleteAccountRow"]
        awaitElement(deleteRow, "Delete account row")
        deleteRow.tap()

        let acknowledgment = app.descendants(matching: .any)["accountDeletion.acknowledgeToggle"]
        acknowledgment.scrollIntoView(in: app)
        XCTAssertTrue(acknowledgment.waitForExistence(timeout: timeout), "Acknowledgment toggle missing")
        acknowledgment.tap()
        XCTAssertTrue(
            acknowledgment.waitUntilSelected(timeout: 5),
            "Acknowledgment never became selected"
        )
        let delete = app.descendants(matching: .any)["accountDeletion.deleteButton"]
        let enableDeadline = Date().addingTimeInterval(5)
        while !delete.isEnabled, Date() < enableDeadline {
            usleep(200_000)
        }
        XCTAssertTrue(delete.isEnabled, "Acknowledgment did not enable deletion")
        delete.tap()
        app.buttons["Delete Permanently"].tap()

        let done = app.descendants(matching: .any)["accountDeletion.doneButton"].firstMatch
        awaitElement(done, "Deletion started confirmation")
        done.tap()
        awaitElement(app.buttons["Continue with Apple"], "Welcome after account deletion")
    }

    /// P5-KYRA-17: review and delete a saved note from the Privacy & Data screen.
    func testStyleMemoriesCanBeReviewedAndDeleted() throws {
        launchMockMain()
        app.tapChromeTab("Profile")

        let privacy = app.descendants(matching: .any)["profile.privacyAndDataRow"]
        privacy.scrollIntoView(in: app)
        privacy.tap()

        let memoriesRow = app.descendants(matching: .any)["privacyAndData.styleMemoriesRow"]
        awaitElement(memoriesRow, "Style Memories privacy row")
        memoriesRow.tap()

        let note = app.staticTexts["Prefers tapered trousers over slim-straight."]
        awaitElement(note, "A user-visible Kyra memory")
        let deleteButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "profile.styleMemories.delete.")
        ).firstMatch
        awaitElement(deleteButton, "Delete memory control")
        deleteButton.tap()

        let confirmDelete = app.buttons["Delete memory"]
        awaitElement(confirmDelete, "Delete memory confirmation")
        confirmDelete.tap()

        XCTAssertTrue(note.waitForNonExistence(timeout: timeout), "Deleted memory remained visible")
    }

    private func launchMockMain(extraArguments: [String] = []) {
        app.launchArguments += [
            "-astra-reset-state",
            "-astra-mock-backend",
            "-astra-skip-onboarding"
        ] + extraArguments
        app.launch()
        awaitElement(app.chromeTabBar, "Main tab bar under mock backend")
    }
}

private extension AstraStyleUITests {
    func assertOnboardingCompletionWasWritten(probe: XCUIElement) {
        let probeLoaded = expectation(
            for: NSPredicate(format: "label BEGINSWITH %@", "timestamp="),
            evaluatedWith: probe
        )
        wait(for: [probeLoaded], timeout: 5)

        let fields = probe.label.split(separator: ";", omittingEmptySubsequences: false)
        XCTAssertEqual(fields.count, 2, "Acceptance probe should return timestamp and write count")
        guard fields.count == 2,
              fields[0].hasPrefix("timestamp="),
              fields[1].hasPrefix("writes="),
              let writeCount = Int(fields[1].dropFirst("writes=".count)) else {
            XCTFail("Acceptance probe returned malformed state: \(probe.label)")
            return
        }

        let timestampString = String(fields[0].dropFirst("timestamp=".count))
        let timestamp = ISO8601DateFormatter().date(from: timestampString)
        XCTAssertNotNil(timestamp, "Completion should be returned as an ISO 8601 timestamp")
        if let timestamp {
            XCTAssertLessThan(
                abs(timestamp.timeIntervalSinceNow),
                120,
                "The timestamp must be the newly written completion, not the seeded fixture value"
            )
        }
        XCTAssertGreaterThanOrEqual(writeCount, 1, "Finishing onboarding must perform a mock repository write")
    }
}

extension AstraStyleUITests {
    /// Spec §22 "Generate outfit". Owner: P4-OUTFIT.
    func testGenerateOutfit() throws {
        launchMockMain()
        let closetDoor = app.buttons["home.style.fromCloset"]
        awaitElement(closetDoor, "Closet outfit entry point")
        closetDoor.tap()

        let generate = app.buttons["outfitBuilder.generateRecommendations"]
        awaitElement(generate, "Closet outfit recommendation builder")
        generate.tap()

        let recommendations = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "outfitBuilder.recommendation.")
        )
        let deadline = Date().addingTimeInterval(timeout)
        while recommendations.count < 3, Date() < deadline {
            usleep(100_000)
        }
        XCTAssertEqual(recommendations.count, 3, "Generation should return three outfit recommendations")

        let expectedOwnedPieces = ["Knit Polo", "Slim Trousers", "Suede Chukka Boots"]
        for itemName in expectedOwnedPieces {
            XCTAssertTrue(
                app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", itemName)).firstMatch.waitForExistence(timeout: timeout),
                "Generated recommendation did not resolve owned closet item: \(itemName)"
            )
        }

        let firstChoice = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "outfitBuilder.chooseRecommendation.")
        ).firstMatch
        firstChoice.scrollIntoView(in: app)
        awaitElement(firstChoice, "Recommendation selection action")
        firstChoice.tap()

        let selectedSlot = app.descendants(matching: .any)["outfitBuilder.slot.top"]
        selectedSlot.scrollIntoView(in: app)
        XCTAssertTrue(selectedSlot.waitForExistence(timeout: timeout))
        XCTAssertTrue(selectedSlot.label.contains("Knit Polo"), "Choosing the recommendation should fill the canvas with its owned top")

        let save = app.buttons["outfitBuilder.save"]
        save.scrollIntoView(in: app)
        awaitElement(save, "Save selected outfit")
        save.tap()
        awaitElement(app.buttons["outfitBuilder.visualize"], "Saved outfit Studio action")
        awaitElement(app.buttons["outfitBuilder.refineWithKyra"], "Saved outfit Kyra refinement action")
    }

    /// Spec §22 "Mark worn". Owner: P4-OUTFIT.
    func testMarkOutfitWorn() throws {
        launchMockMain()
        let wear = app.descendants(matching: .any)["home.wearThis"]
        wear.scrollIntoView(in: app)
        awaitElement(wear, "Wear This")
        wear.tap()
        let deadline = Date().addingTimeInterval(timeout)
        while wear.isEnabled, Date() < deadline {
            usleep(200_000)
        }
        XCTAssertFalse(wear.isEnabled, "Wear This did not become the one-shot completed state")
        XCTAssertTrue(
            app.buttons["Worn today"].exists || wear.label == "Worn today",
            "Wear This completed without visible confirmation"
        )

        let review = app.buttons["home.monthlyReview"]
        review.scrollIntoView(in: app)
        awaitElement(review, "Monthly Review entry point")
        review.tap()
        let wearCount = app.staticTexts["monthlyReview.statValue.looks-worn"]
        awaitElement(wearCount, "Monthly Review wear count")
        // Home opens the most recently completed month. Today's successful
        // wear must not leak into that historical review.
        XCTAssertEqual(wearCount.label, "0", "Today's wear must be excluded from last month's review")
    }

}
