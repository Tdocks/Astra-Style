import XCTest

/// Runs Kyra through the real app, local Supabase Auth/PostgREST/Edge Function
/// stack, and a disposable local provider stub. The host harness supplies a
/// mode-0600 fixture file; no token is placed in launch arguments or output.
@MainActor
final class LocalKyraAcceptanceUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    func testAskKyraRendersOnlyFixtureOwnersClosetItems() throws {
        continueAfterFailure = false
        guard let path = Self.fixturePath() else {
            throw XCTSkip("Local Kyra fixture is not configured for this run.")
        }
        let fixture = try Self.readFixture(at: path)
        guard Self.isLoopbackHTTPURL(fixture.supabaseURL), !fixture.itemNames.isEmpty else {
            XCTFail("Local Kyra fixture must point to loopback Supabase and include seeded closet item names.")
            return
        }

        launchLocalSession(fixture, path: path)
        sendKyraPrompt()
        assertFixtureOutfitCard(itemNames: fixture.itemNames)
        app.terminate()
    }

    private func launchLocalSession(_ fixture: Fixture, path: String) {
        app.launchArguments = [
            "-astra-local-qa-kyra",
            "-astra-skip-onboarding",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment = [
            "ASTRA_LOCAL_SUPABASE_URL": fixture.supabaseURL,
            "ASTRA_LOCAL_SUPABASE_ANON_KEY": fixture.supabaseAnonKey,
            "ASTRA_LOCAL_QA_FIXTURE_PATH": path
        ]
        addUIInterruptionMonitor(withDescription: "Apple Account Verification") { alert in
            guard alert.label.contains("Apple Account Verification") else { return false }
            let notNow = alert.buttons["Not Now"]
            guard notNow.exists else { return false }
            notNow.tap()
            return true
        }
        app.launch()

        dismissAppleAccountVerificationIfPresent()
        XCTAssertTrue(app.chromeTabBar.waitForExistence(timeout: 45), "The local fixture session did not reach Home.")
    }

    private func sendKyraPrompt() {
        let askButton = app.descendants(matching: .any)["kyra.ask"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 30), "Ask Kyra was not reachable.")
        dismissAppleAccountVerificationIfPresent()
        askButton.tap()

        let composer = app.textFields["kyra.composer.field"]
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "Kyra's composer did not load.")
        composer.tap()
        composer.typeText("Make an outfit using my local test closet.")
        let sendButton = app.buttons["kyra.composer.send"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 10), "The send button did not appear.")
        XCTAssertTrue(sendButton.isEnabled, "The message should be ready to send.")
        dismissAppleAccountVerificationIfPresent()
        sendButton.tap()
    }

    private func assertFixtureOutfitCard(itemNames: [String]) {
        let outfitCard = app.descendants(matching: .any)["kyra.card.outfit"].firstMatch
        XCTAssertTrue(outfitCard.waitForExistence(timeout: 60), "Kyra did not render an outfit card from the local provider stub.")
        for itemName in itemNames {
            let ownedItem = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", itemName)
            ).firstMatch
            XCTAssertTrue(
                ownedItem.waitForExistence(timeout: 10),
                "Kyra's outfit card did not resolve fixture closet item '\(itemName)'."
            )
        }
    }

    private func dismissAppleAccountVerificationIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts["Apple Account Verification"]
        guard alert.waitForExistence(timeout: 2) else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.12)).tap()
        if alert.exists {
            let notNow = alert.buttons["Not Now"]
            XCTAssertTrue(notNow.exists, "Apple verification alert must offer Not Now")
            notNow.tap()
        }
        XCTAssertFalse(alert.exists, "Dismiss the Apple verification alert before the local Kyra flow")
    }

    private static func readFixture(at path: String) throws -> Fixture {
        let fileURL = URL(fileURLWithPath: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard
            let size = attributes[.size] as? NSNumber,
            let permissions = attributes[.posixPermissions] as? NSNumber,
            size.intValue > 0,
            size.intValue <= 16_384,
            (permissions.intValue & 0o077) == 0
        else {
            throw XCTSkip("Local Kyra fixture must be a small file with owner-only permissions.")
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    private static func fixturePath() -> String? {
        if let path = ProcessInfo.processInfo.environment["ASTRA_LOCAL_QA_FIXTURE_PATH"] {
            return path
        }
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let repoMarker = directory.appendingPathComponent(".git")
            let fixture = directory.appendingPathComponent("ios/.local-qa/kyra-fixture.json")
            if FileManager.default.fileExists(atPath: repoMarker.path),
               FileManager.default.fileExists(atPath: fixture.path) {
                return fixture.path
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    private static func isLoopbackHTTPURL(_ value: String) -> Bool {
        guard
            let url = URL(string: value),
            url.scheme?.lowercased() == "http",
            url.user == nil,
            url.password == nil,
            url.query == nil,
            url.fragment == nil
        else { return false }
        let host = url.host?.lowercased()
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private struct Fixture: Decodable {
        let userID: UUID
        let supabaseURL: String
        let supabaseAnonKey: String
        let itemNames: [String]

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case supabaseURL = "supabase_url"
            case supabaseAnonKey = "supabase_anon_key"
            case itemNames = "item_names"
        }
    }
}
