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

}

@MainActor
extension PersonalStyleFeatureUITests {
    func testReceiptCaptureIsReachableFromCloset() throws {
        launchMockMain()
        app.tapChromeTab("Closet")
        let scan = app.buttons["closet.header.scan"]
        awaitElement(scan, "Closet scan menu")
        scan.tap()
        let receipt = app.buttons["Receipt or label"]
        awaitElement(receipt, "Receipt mode")
        receipt.tap()
        awaitElement(app.navigationBars["Receipt / label"], "Receipt capture screen")
        awaitElement(app.buttons["Choose photo"], "Receipt photo import")
        awaitElement(app.buttons["Take photo"], "Receipt camera action")
    }

    /// Home opens the image flow without requiring a selfie or closet.
    func testHomeStyleInspiration() throws {
        launchMockMain()
        let inspiration = app.buttons["home.style.inspiration"]
        inspiration.scrollIntoView(in: app)
        awaitElement(inspiration, "Home inspiration action")
        inspiration.tap()
        if !app.navigationBars["Inspiration"].waitForExistence(timeout: 3) { inspiration.tap() }
        awaitElement(app.navigationBars["Inspiration"], "Inspiration screen")
        let allowance = app.staticTexts["home.inspiration.allowance"]
        awaitElement(allowance, "Preview allowance")
        XCTAssertTrue(allowance.label.contains("20 of 20"))
        let generate = app.buttons["home.inspiration.generate"]
        awaitElement(generate, "Generate image action")
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: generate)], timeout: timeout) == .completed)
        generate.scrollIntoView(in: app)
        generate.tap()
        awaitElement(app.descendants(matching: .any)["home.inspiration.image"].firstMatch, "Completed estimate container")
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: generate)], timeout: timeout) == .completed)
        generate.scrollIntoView(in: app)
        XCTAssertTrue(allowance.label.contains("19 of 20"))
        XCTAssertEqual(generate.label, "Try another look")
        let adjustment = app.textFields["home.inspiration.adjustment"]
        adjustment.scrollIntoView(in: app)
        adjustment.tap()
        adjustment.typeText("More casual")
        XCTAssertEqual(generate.label, "Apply my changes")
        generate.scrollIntoView(in: app)
        generate.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: generate)], timeout: timeout) == .completed)
        XCTAssertEqual(generate.label, "Try another look")
        generate.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: generate)], timeout: timeout) == .completed)
    }

    /// Home keeps its three recommendations and previews the exact chosen pieces.
    func testHomeClosetBasedOutfit() throws {
        launchMockMain()
        ClosetBasedPreviewUITestDriver(app: app, timeout: timeout).run()
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

    func testStudioCompareGeneratedLooks() throws {
        try compareGeneratedLooks()
    }

    func testStudioSavePrivateCollection() throws {
        try savePrivateCollection()
    }

    func testStudioTrackedImageRemoval() throws {
        app.launchArguments += ["-astra-test-pending-image-removal"]
        try deleteStudioEstimate()
    }

    func testReferencePhotoTrackedCascade() throws {
        try referencePhotoCascade()
    }

    func testReferencePhotoTrackedCascadeLightAccessibility() throws {
        app.launchArguments += ["-astra-theme", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        try referencePhotoCascade()
    }

    private func referencePhotoCascade() throws {
        app.launchArguments += ["-astra-test-reference-photo", "-astra-test-pending-image-removal"]
        launchMockMain()
        app.tapChromeTab("Profile")
        let privacy = app.descendants(matching: .any)["profile.privacyAndDataRow"]
        privacy.scrollIntoView(in: app); privacy.tap()
        let references = app.buttons["privacyAndData.referencePhotosRow"]
        awaitElement(references, "Reference photos privacy row")
        references.scrollIntoView(in: app); references.tap()
        let count = app.staticTexts["Removing this also deletes 3 saved Studio previews."]
        count.scrollIntoView(in: app)
        awaitElement(count, "Transitive variation count")
        let remove = app.buttons["profile.referencePhotos.delete.1"]
        remove.scrollIntoView(in: app); remove.tap()
        let confirm = app.buttons.matching(identifier: "profile.referencePhotos.confirmDelete").firstMatch
        awaitElement(confirm, "Reference cascade confirmation"); confirm.tap()
        let empty = app.staticTexts["No reference photos saved"]
        empty.scrollIntoView(in: app); awaitElement(empty, "Reference removed after accepted cascade")
        let check = app.buttons["profile.referencePhotos.checkRemoval"]
        check.scrollIntoView(in: app); awaitElement(check, "Pending file cleanup remains reachable")
        check.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: check)], timeout: timeout) == .completed)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Reference photo pending removal"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.tapChromeTab("Studio")
        awaitElement(app.buttons["studio.empty.start"], "Every derived variation removed from Studio")
    }

    func testStudioTrackedRemovalLightAccessibility() throws {
        app.launchArguments += ["-astra-test-pending-image-removal", "-astra-theme", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        try deleteStudioEstimate()
    }

    private func deleteStudioEstimate() throws {
        launchMockMain()
        let inspiration = app.buttons["home.style.inspiration"]
        inspiration.scrollIntoView(in: app); inspiration.tap()
        if !app.navigationBars["Inspiration"].waitForExistence(timeout: 3) { inspiration.tap() }
        let generate = app.buttons["home.inspiration.generate"]
        awaitElement(generate, "Generate estimate")
        generate.scrollIntoView(in: app); generate.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: generate)], timeout: timeout) == .completed)
        app.buttons["Close"].tap()
        app.tapChromeTab("Studio")
        let deletion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "studio.generation.delete.")).firstMatch
        awaitElement(deletion, "Remove estimate action")
        deletion.scrollIntoView(in: app); deletion.tap()
        let confirm = app.buttons.matching(identifier: "studio.delete.confirm").firstMatch
        awaitElement(confirm, "Confirm estimate removal"); confirm.tap()
        awaitElement(app.buttons["studio.empty.start"], "Gallery empty after accepted deletion")
        let check = app.buttons["studio.cleanup.check"]
        awaitElement(check, "Tracked server removal remains visible")
        check.scrollIntoView(in: app); check.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: check)], timeout: timeout) == .completed)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Studio pending image removal"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStudioSaveCollectionLightAccessibility() throws {
        app.launchArguments += ["-astra-theme", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        try savePrivateCollection()
    }

    private func savePrivateCollection() throws {
        launchMockMain()
        let inspiration = app.buttons["home.style.inspiration"]
        inspiration.scrollIntoView(in: app)
        inspiration.tap()
        if !app.navigationBars["Inspiration"].waitForExistence(timeout: 3) { inspiration.tap() }
        let generate = app.buttons["home.inspiration.generate"]
        awaitElement(generate, "Image generation")
        generate.scrollIntoView(in: app)
        generate.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: generate)], timeout: timeout) == .completed)
        app.buttons["Close"].tap()
        app.tapChromeTab("Studio")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND NOT identifier CONTAINS %@", "studio.generation.", ".delete.")).firstMatch
        awaitElement(card, "Completed estimate")
        card.tap()
        let save = app.buttons["studio.detail.save"]
        save.scrollIntoView(in: app)
        save.tap()
        awaitElement(app.navigationBars["Save look"], "Private collection picker")
        app.buttons["studio.collection.new"].tap()
        let field = app.alerts.textFields["Collection name"]
        awaitElement(field, "Collection name")
        field.tap(); field.typeText("Everyday QA")
        app.alerts.buttons["Create"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "studio.collection.", "Everyday QA")).firstMatch
        awaitElement(saved, "Saved collection")
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Saved"), object: saved)], timeout: timeout) == .completed)
        app.buttons["Done"].tap()
        app.navigationBars["Estimate"].buttons.element(boundBy: 0).tap()
        app.buttons["studio.lookbooks.open"].tap()
        let collection = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "studio.collection.", "Everyday QA")).firstMatch
        awaitElement(collection, "Saved collection in Studio")
        collection.tap()
        awaitElement(app.navigationBars["Everyday QA"], "Saved lookbook")
        let estimate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "studio.savedLook.")).firstMatch
        awaitElement(estimate, "Retained visual estimate")
        estimate.scrollIntoView(in: app)
        app.buttons["Remove from collection"].tap()
        app.alerts.buttons["Remove"].tap()
        awaitElement(app.staticTexts["No looks saved here yet"], "Empty collection after removal")
    }

    func testStudioPrepareShareableEstimate() throws {
        launchMockMain()
        let inspiration = app.buttons["home.style.inspiration"]
        inspiration.scrollIntoView(in: app)
        inspiration.tap()
        if !app.navigationBars["Inspiration"].waitForExistence(timeout: 3) { inspiration.tap() }
        let generate = app.buttons["home.inspiration.generate"]
        awaitElement(generate, "Image generation")
        generate.scrollIntoView(in: app)
        generate.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: generate)], timeout: timeout) == .completed)
        app.buttons["Close"].tap()
        app.tapChromeTab("Studio")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND NOT identifier CONTAINS %@", "studio.generation.", ".delete.")).firstMatch
        awaitElement(card, "Completed Studio estimate")
        card.tap()
        awaitElement(app.descendants(matching: .any)["studio.visualEstimateDisclosure"], "Visible estimate disclosure")
        let export = app.buttons["studio.detail.export"]
        awaitElement(export, "Prepare private image for sharing")
        export.scrollIntoView(in: app)
        export.tap()
        let share = app.buttons["studio.detail.share"]
        awaitElement(share, "Share prepared estimate")
        XCTAssertTrue(share.isEnabled)
    }

    func testStudioHighResolutionExportConfirmationAndRecoveryDark() throws {
        try highResolutionExportConfirmationAndRecovery(lightAccessibility: false)
    }

    func testStudioHighResolutionExportConfirmationAndRecoveryLightAccessibility() throws {
        try highResolutionExportConfirmationAndRecovery(lightAccessibility: true)
    }

    private func highResolutionExportConfirmationAndRecovery(lightAccessibility: Bool) throws {
        app.launchArguments += ["-astra-test-reference-photo"]
        if lightAccessibility {
            app.launchArguments += ["-astra-theme", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        } else {
            app.launchArguments += ["-astra-theme", "dark"]
        }
        launchMockMain()
        app.tapChromeTab("Studio")
        let sourceIdentifier = openPhotoSourceEstimate()
        confirmHighResolutionExport(lightAccessibility: lightAccessibility)
        assertHighResolutionChildAndReopen(sourceIdentifier: sourceIdentifier, lightAccessibility: lightAccessibility)
    }

    private func openPhotoSourceEstimate() -> String {
        let sourceCard = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND NOT identifier CONTAINS %@", "studio.generation.", ".delete.")
        ).firstMatch
        awaitElement(sourceCard, "Completed photo-source estimate")
        sourceCard.scrollIntoView(in: app)
        let sourceIdentifier = sourceCard.identifier
        sourceCard.tap()
        return sourceIdentifier
    }

    private func confirmHighResolutionExport(lightAccessibility: Bool) {
        let export = app.buttons["studio.detail.exportHiRes"]
        export.scrollIntoView(in: app)
        awaitElement(export, "Higher-quality export action")
        XCTAssertTrue(export.isHittable, "The export action must remain reachable at the selected text size")
        export.tap()

        let firstConfirmation = app.alerts["Export a higher-quality estimate?"]
        awaitElement(firstConfirmation, "Credit and photo-consent confirmation")
        XCTAssertTrue(firstConfirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "remaining Premium Studio renders")).firstMatch.exists)
        XCTAssertTrue(firstConfirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "process the original photo again")).firstMatch.exists)
        XCTAssertTrue(firstConfirmation.buttons["Agree and export"].exists)

        if !lightAccessibility {
            let confirmationScreenshot = XCTAttachment(screenshot: app.screenshot())
            confirmationScreenshot.name = "Studio higher-quality confirmation dark"
            confirmationScreenshot.lifetime = .keepAlways
            add(confirmationScreenshot)

            firstConfirmation.buttons["Cancel"].tap()
            XCTAssertFalse(app.staticTexts["Higher quality export"].waitForExistence(timeout: 1))
            export.scrollIntoView(in: app)
            export.tap()
            let secondConfirmation = app.alerts["Export a higher-quality estimate?"]
            awaitElement(secondConfirmation, "Confirmation after cancel")
            XCTAssertTrue(
                secondConfirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "one of your 17 remaining")).firstMatch.exists,
                "Cancelling must not reserve a render"
            )
            secondConfirmation.buttons["Agree and export"].tap()
        } else {
            XCTAssertTrue(firstConfirmation.buttons["Agree and export"].isHittable)
            firstConfirmation.buttons["Agree and export"].tap()
        }
    }

    private func assertHighResolutionChildAndReopen(sourceIdentifier: String, lightAccessibility: Bool) {
        let childTitle = app.staticTexts["Higher quality export"]
        awaitElement(childTitle, "Accepted higher-quality child")
        let image = app.descendants(matching: .any)["studio.detail.exportHiRes.image"]
        awaitElement(image, "Completed higher-quality image")
        XCTAssertGreaterThanOrEqual(app.descendants(matching: .any).matching(identifier: "studio.visualEstimateDisclosure").count, 2,
                                    "Both source and child images must retain the visual-estimate disclosure")

        let resultScreenshot = XCTAttachment(screenshot: app.screenshot())
        resultScreenshot.name = lightAccessibility ? "Studio higher-quality export light accessibility" : "Studio higher-quality export dark"
        resultScreenshot.lifetime = .keepAlways
        add(resultScreenshot)

        app.navigationBars["Estimate"].buttons.element(boundBy: 0).tap()
        let originalCard = app.buttons[sourceIdentifier]
        awaitElement(originalCard, "Original estimate remains in the gallery")
        originalCard.tap()
        awaitElement(childTitle, "Recovered child when reopening the source detail")
        XCTAssertFalse(app.buttons["studio.detail.exportHiRes"].exists, "A recovered lineage must not offer a second charged export")
    }

    func testStudioEditImageDescription() throws { try editImageDescription() }

    func testStudioEditImageDescriptionLightAccessibility() throws {
        app.launchArguments += ["-astra-test-accessibility-size", "-astra-test-light-theme"]
        try editImageDescription()
    }

    private func editImageDescription() throws {
        app.launchArguments += ["-astra-test-reference-photo"]
        launchMockMain()
        app.tapChromeTab("Studio")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND NOT identifier CONTAINS %@", "studio.generation.", ".delete.")).firstMatch
        awaitElement(card, "Completed Studio estimate"); card.tap()
        let edit = app.buttons["studio.detail.editDescription"]
        awaitElement(edit, "Edit image description"); edit.scrollIntoView(in: app); edit.tap()
        let field = app.textViews["studio.description.text"].exists ? app.textViews["studio.description.text"] : app.textFields["studio.description.text"]
        awaitElement(field, "Editable description")
        app.buttons["studio.description.reset"].tap()
        field.tap(); field.typeText("Navy trousers and a white linen shirt.")
        app.buttons["studio.description.save"].tap()
        awaitElement(edit, "Description saved"); edit.scrollIntoView(in: app); edit.tap()
        awaitElement(field, "Saved description editor")
        XCTAssertEqual(field.value as? String, "Navy trousers and a white linen shirt.")
        app.buttons["studio.description.reset"].tap()
        app.buttons["studio.description.save"].tap()
        awaitElement(edit, "Automatic description restored")
    }

    func testStudioCompareLightAccessibility() throws {
        app.launchArguments += ["-astra-theme", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        try compareGeneratedLooks()
    }

    private func compareGeneratedLooks() throws {
        launchMockMain()
        let inspiration = app.buttons["home.style.inspiration"]
        inspiration.scrollIntoView(in: app)
        inspiration.tap()
        if !app.navigationBars["Inspiration"].waitForExistence(timeout: 3) { inspiration.tap() }
        let generate = app.buttons["home.inspiration.generate"]
        awaitElement(generate, "Image generation")
        for _ in 0..<2 {
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: generate)], timeout: timeout) == .completed)
            generate.scrollIntoView(in: app)
            generate.tap()
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: generate)], timeout: timeout) == .completed)
        }
        app.buttons["Close"].tap()
        app.tapChromeTab("Studio")
        let select = app.buttons["studio.compare.select"]
        awaitElement(select, "Comparison selection")
        XCTAssertTrue(select.isEnabled)
        select.tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND NOT identifier CONTAINS %@", "studio.generation.", ".delete."))
        XCTAssertGreaterThan(cards.count, 0)
        let firstID = cards.element(boundBy: 0).identifier
        let first = app.buttons[firstID]
        first.scrollIntoView(in: app)
        first.tap()
        XCTAssertEqual(first.value as? String, "Selected")
        let second = cards.matching(NSPredicate(format: "identifier != %@", firstID)).firstMatch
        for _ in 0..<5 {
            if second.exists { break }
            app.swipeUp()
        }
        awaitElement(second, "Second completed estimate")
        second.scrollIntoView(in: app)
        second.tap()
        XCTAssertEqual(second.value as? String, "Selected")
        let open = app.buttons["studio.compare.open"]
        XCTAssertTrue(open.isEnabled)
        open.tap()
        awaitElement(app.navigationBars["Compare looks"], "Completed comparison screen")
        awaitElement(app.staticTexts["Look 1"], "First estimate")
        app.staticTexts["Look 2"].scrollIntoView(in: app)
        awaitElement(app.staticTexts["Look 2"], "Second estimate")
        XCTAssertGreaterThanOrEqual(app.descendants(matching: .any).matching(identifier: "studio.visualEstimateDisclosure").count, 2)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Studio comparison"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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

@MainActor
extension PersonalStyleFeatureUITests {
    func testMirrorCaptureIsReachableFromCloset() throws {
        launchMockMain()
        app.tapChromeTab("Closet")
        let scan = app.buttons["closet.header.scan"]
        awaitElement(scan, "Closet scan menu")
        scan.tap()
        let mirror = app.buttons["Mirror photo"]
        awaitElement(mirror, "Mirror mode")
        mirror.tap()
        awaitElement(app.navigationBars["Mirror photo"], "Mirror capture screen")
        awaitElement(app.buttons["Choose photo"], "Mirror photo import")
        awaitElement(app.buttons["Take mirror photo"], "Mirror camera action")
        let save = app.buttons["Save private reference"]
        save.scrollIntoView(in: app)
        awaitElement(save, "Reference save action")
        XCTAssertFalse(save.isEnabled, "Saving must require a photo and permission")
    }
}

@MainActor
extension PersonalStyleFeatureUITests {
    func testClosetItemInsightsAreReachable() throws {
        launchMockMain()
        app.tapChromeTab("Closet")
        let item = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "closet.grid.item.")
        ).firstMatch
        item.scrollIntoView(in: app)
        awaitElement(item, "Closet piece")
        item.tap()
        let insights = app.staticTexts["closet.item.insights.title"]
        insights.scrollIntoView(in: app)
        awaitElement(insights, "Item insights section")
        let pairings = app.staticTexts["closet.item.insights.pairings"]
        pairings.scrollIntoView(in: app)
        awaitElement(pairings, "Pairing suggestions")
        XCTAssertFalse(app.buttons["Retry insights"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Item insights"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

@MainActor
extension PersonalStyleFeatureUITests {
    func testItemGalleryOpensSavedLook() throws {
        try verifyItemGallery()
    }

    func testItemGalleryAtLargestTextSize() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        try verifyItemGallery()
    }

    private func verifyItemGallery() throws {
        launchMockMain()
        app.tapChromeTab("Closet")
        let search = app.textFields["Name, brand, or colour"]
        search.scrollIntoView(in: app)
        awaitElement(search, "Closet search")
        search.tap()
        search.typeText("Knit Polo\n")
        let item = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "closet.grid.item.")
        ).firstMatch
        item.scrollIntoView(in: app)
        awaitElement(item, "Saved-look garment")
        item.tap()
        let open = app.buttons["closet.item.insights.openLook"]
        open.scrollIntoView(in: app, maxSwipes: 12)
        awaitElement(open, "Saved look gallery action")
        XCTAssertTrue(app.staticTexts["Client Meeting, Elevated Casual"].exists)
        open.tap()
        awaitElement(app.buttons["outfitDetail.action.askKyra"], "Saved outfit detail")
    }
}
