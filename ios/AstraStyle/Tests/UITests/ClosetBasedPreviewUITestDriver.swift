import XCTest

@MainActor
struct ClosetBasedPreviewUITestDriver {
    let app: XCUIApplication
    let timeout: TimeInterval

    func run() {
        let homeAction = app.buttons["home.style.fromCloset"]
        homeAction.scrollIntoView(in: app)
        require(homeAction, "Home closet outfit action")
        homeAction.tap()
        let chosenNames = chooseOneRecommendation()
        previewExactly(chosenNames)
        generateEditAndReroll(chosenNames)
    }

    private func chooseOneRecommendation() -> Set<String> {
        let generate = app.buttons["outfitBuilder.generateRecommendations"]
        require(generate, "Three-outfit recommendation builder")
        generate.tap()

        let choices = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "outfitBuilder.chooseRecommendation.")
        )
        let deadline = Date().addingTimeInterval(timeout)
        while choices.count < 3, Date() < deadline {
            usleep(100_000)
        }
        XCTAssertEqual(choices.count, 3, "The builder must retain all three outfit ideas")

        let choice = choices.firstMatch
        choice.scrollIntoView(in: app)
        require(choice, "Choose one owned outfit recommendation")
        let identifier = choice.identifier.replacingOccurrences(
            of: "outfitBuilder.chooseRecommendation.",
            with: ""
        )
        let pieces = app.staticTexts["outfitBuilder.recommendationItems.\(identifier)"]
        require(pieces, "Recommendation's exact owned pieces")
        let names = Set(pieces.label.components(separatedBy: " · "))
        choice.tap()
        return names
    }

    private func previewExactly(_ names: Set<String>) {
        let preview = app.buttons["outfitBuilder.previewPieces"]
        preview.scrollIntoView(in: app)
        require(preview, "Preview selected pieces action")
        XCTAssertTrue(preview.isEnabled)
        preview.tap()
        require(app.navigationBars["My closet look"], "Exact closet selection preview")

        let selectedItems = app.staticTexts["home.inspiration.selectedItems"]
        require(selectedItems, "Selection preserved in the image flow")
        XCTAssertEqual(Set(selectedItems.label.components(separatedBy: ", ")), names)
    }

    private func generateEditAndReroll(_ names: Set<String>) {
        let generate = app.buttons["home.inspiration.generate"]
        generate.scrollIntoView(in: app)
        waitUntilEnabled(generate)
        generate.tap()
        require(app.descendants(matching: .any)["home.inspiration.image"].firstMatch, "Closet estimate")
        let imageInput = app.staticTexts["home.inspiration.imageBasedOn"]
        assertImageUses(names, imageInput: imageInput)

        let adjustment = app.textFields["home.inspiration.adjustment"]
        adjustment.scrollIntoView(in: app)
        adjustment.tap()
        adjustment.typeText("Make the proportions more relaxed")
        XCTAssertEqual(generate.label, "Apply my changes")
        generate.scrollIntoView(in: app)
        generate.tap()
        waitUntilEnabled(generate)

        XCTAssertEqual(generate.label, "Try another look")
        generate.tap()
        waitUntilEnabled(generate)
        assertImageUses(names, imageInput: imageInput)
    }

    private func assertImageUses(_ names: Set<String>, imageInput: XCUIElement) {
        require(imageInput, "Image input description")
        for name in names {
            XCTAssertTrue(imageInput.label.contains(name), "The image should keep selected piece: \(name)")
        }
    }

    private func waitUntilEnabled(_ element: XCUIElement) {
        XCTAssertTrue(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)],
                timeout: timeout
            ) == .completed
        )
    }

    private func require(_ element: XCUIElement, _ description: String) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Never appeared: \(description)")
    }
}
