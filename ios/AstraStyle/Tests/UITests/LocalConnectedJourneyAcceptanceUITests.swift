import XCTest

/// Extends the local Kyra acceptance into a signed-in persistence check. The
/// app still talks to the local Supabase stack; the test then verifies the
/// resulting records through the same fixture owner's JWT and RLS policies.
@MainActor
final class LocalConnectedJourneyAcceptanceUITests: XCTestCase {
    private let prompt = "Make an outfit using my local test closet."

    func testKyraOutfitPersistsForTheSignedInFixtureOwner() async throws {
        try await runJourney(degraded: false)
    }

    func testDegradedNetworkConnectedJourney() async throws {
        try await runJourney(degraded: true)
    }

    private func runJourney(degraded: Bool) async throws {
        continueAfterFailure = false
        guard let path = Self.fixturePath() else {
            throw XCTSkip("Local Kyra fixture is not configured for this run.")
        }
        let fixture = try Self.readFixture(at: path)
        guard Self.isLoopbackHTTPURL(fixture.supabaseURL), !fixture.itemNames.isEmpty else {
            XCTFail("The connected journey requires a loopback Supabase fixture with closet items.")
            return
        }

        let app = launchLocalSession(fixture, path: path)
        if degraded { try await fixture.inject("closet-read", method: "GET", path: "/rest/v1/closet_items") }
        verifySessionSurvivesRelaunch(in: app, fixture: fixture)
        if degraded { try await fixture.inject("kyra-send", method: "POST", path: "/functions/v1/kyra/respond") }
        sendKyraRequest(in: app, itemNames: fixture.itemNames, retryFailure: degraded)
        let outfitID = try await verifyPersistedKyraOutfit(for: fixture)
        if degraded {
            try await fixture.inject("wear-response-lost", method: "POST",
                                     path: "/functions/v1/outfits/record-wear", mode: "drop_after")
        }
        try await markOutfitWorn(outfitID, in: app, fixture: fixture)
        if degraded { try await verifyOfflineWearReplay(in: app, outfitID: outfitID, fixture: fixture) }
        verifyMonthlyReview(in: app)
        if degraded { try await fixture.inject("delete-retry", method: "DELETE", path: "/functions/v1/account") }
        try await deleteFixtureAccount(in: app, fixture: fixture)
        if degraded { try await fixture.verifyFaultsConsumed() }
        app.terminate()
    }

    private func launchLocalSession(_ fixture: Fixture, path: String) -> XCUIApplication {
        let app = XCUIApplication()
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
        app.launch()
        XCTAssertTrue(
            app.chromeTabBar.waitForExistence(timeout: 45),
            "The signed-in fixture session did not reach Home."
        )
        return app
    }

    private func verifySessionSurvivesRelaunch(in app: XCUIApplication, fixture: Fixture) {
        app.terminate()
        // Keep the local endpoint but bypass fixture credential installation.
        // Bootstrap must restore the actual saved Keychain session.
        app.launchArguments.append("-astra-local-qa-restore")
        app.launchEnvironment.removeValue(forKey: "ASTRA_LOCAL_QA_FIXTURE_PATH")
        app.launch()
        XCTAssertTrue(app.chromeTabBar.waitForExistence(timeout: 45),
                      "Relaunch did not restore the persisted session without fixture injection.")
        app.tapChromeTab("Closet")
        for name in fixture.itemNames {
            let item = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", name)
            ).firstMatch
            item.scrollIntoView(in: app)
            XCTAssertTrue(item.waitForExistence(timeout: 30),
                          "Restored session did not load its owner's closet.")
        }
        app.tapChromeTab("Home")
    }

    private func sendKyraRequest(in app: XCUIApplication, itemNames: [String], retryFailure: Bool = false) {
        let ask = app.descendants(matching: .any)["kyra.ask"]
        XCTAssertTrue(
            ask.waitForExistence(timeout: 30),
            "Ask Kyra was not reachable from the signed-in app."
        )
        ask.tap()

        let composer = app.textFields["kyra.composer.field"]
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "Kyra's composer did not load.")
        composer.tap()
        composer.typeText(prompt)
        let send = app.buttons["kyra.composer.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10), "The Kyra request was not ready to send.")
        send.tap()
        if retryFailure {
            let retry = app.buttons["kyra.message.retry"].firstMatch
            XCTAssertTrue(retry.waitForExistence(timeout: 30), "Failed Kyra turn must expose a retry.")
            retry.tap()
        }

        let card = app.descendants(matching: .any)["kyra.card.outfit"].firstMatch
        XCTAssertTrue(
            card.waitForExistence(timeout: 60),
            "Kyra did not render the local fixture outfit."
        )
        for name in itemNames {
            let item = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", name)
            ).firstMatch
            XCTAssertTrue(
                item.waitForExistence(timeout: 10),
                "The outfit card omitted a fixture closet item."
            )
        }
    }

    private func verifyPersistedKyraOutfit(for fixture: Fixture) async throws -> String {
        let closetRows = try await fixture.requestRows(
            table: "closet_items",
            query: "select=id,name,user_id&user_id=eq.\(fixture.userID.uuidString.lowercased())"
        )
        XCTAssertFalse(
            closetRows.isEmpty,
            "The signed-in owner could not read the seeded closet through RLS."
        )
        let ownerID = fixture.userID.uuidString.lowercased()
        XCTAssertTrue(closetRows.allSatisfy { $0["user_id"] as? String == ownerID })
        let ownerItemIDs = Set(closetRows.compactMap { $0["id"] as? String })

        let outfits = try await fixture.requestRows(
            table: "outfits",
            query: "select=id,user_id,source&user_id=eq.\(ownerID)" +
                "&source=eq.kyra_suggested&order=created_at.desc&limit=10"
        )
        guard let outfit = outfits.first, let outfitID = outfit["id"] as? String else {
            XCTFail("Kyra's rendered outfit was not persisted for the signed-in owner.")
            throw JourneyError.requestFailed
        }
        XCTAssertEqual(outfits.count, 1, "Retry must not create duplicate Kyra outfits.")
        XCTAssertEqual(outfit["user_id"] as? String, ownerID)
        XCTAssertEqual(outfit["source"] as? String, "kyra_suggested")

        let outfitItems = try await fixture.requestRows(
            table: "outfit_items",
            query: "select=id,user_id,outfit_id,closet_item_id&user_id=eq.\(ownerID)" +
                "&outfit_id=eq.\(outfitID)"
        )
        XCTAssertFalse(outfitItems.isEmpty, "Kyra's saved outfit has no persisted garment links.")
        XCTAssertTrue(outfitItems.allSatisfy { row in
            row["user_id"] as? String == ownerID
                && row["outfit_id"] as? String == outfitID
                && ownerItemIDs.contains(row["closet_item_id"] as? String ?? "")
        }, "The persisted outfit must link only to this owner's closet items.")

        let assistantMessages = try await fixture.requestRows(
            table: "kyra_messages",
            query: "select=id,user_id,thread_id,role,content,structured_payload" +
                "&user_id=eq.\(ownerID)&role=eq.assistant&order=created_at.desc&limit=10"
        )
        XCTAssertEqual(assistantMessages.count, 1, "Retry must not create duplicate assistant replies.")
        XCTAssertTrue(assistantMessages.contains { row in
            row["user_id"] as? String == ownerID
                && row["content"] is String
        }, "The connected Kyra turn was not readable from the fixture owner's message history.")
        return outfitID
    }

    private func markOutfitWorn(
        _ outfitID: String,
        in app: XCUIApplication,
        fixture: Fixture
    ) async throws {
        // Kyra's create_outfit result is already a saved outfit. Open that
        // owner-scoped result from the real Closet UI and record a wear.
        app.buttons["kyra.close"].tap()
        app.tapChromeTab("Closet")
        let openLook = app.buttons["closet.looks.open"].firstMatch
        XCTAssertTrue(
            openLook.waitForExistence(timeout: 30),
            "The saved Kyra outfit was not reachable in Closet."
        )
        openLook.tap()
        let markWorn = app.descendants(matching: .any)["outfitDetail.action.markWorn"]
        XCTAssertTrue(
            markWorn.waitForExistence(timeout: 30),
            "The saved outfit detail did not expose Mark Worn."
        )
        markWorn.tap()
        try await fixture.waitForWear(outfitID: outfitID)
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: markWorn)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 30), .completed,
                       "Wear recovery did not finish.")
        try await fixture.waitForWear(outfitID: outfitID)
    }

}

@MainActor
extension LocalConnectedJourneyAcceptanceUITests {
    private func verifyOfflineWearReplay(in app: XCUIApplication, outfitID: String, fixture: Fixture) async throws {
        try await fixture.inject("wear-offline-fallback", method: "POST",
                                 path: "/functions/v1/outfits/record-wear", count: 4)
        let mark = app.descendants(matching: .any)["outfitDetail.action.markWorn"]
        mark.tap()
        let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: mark)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 10), .completed)
        // The queue fallback completes only after all four attempts fail.
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: mark)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 30), .completed)
        try await fixture.inject("offline-replay-response-lost", method: "POST",
                                 path: "/rest/v1/outfit_wears", mode: "drop_after")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.chromeTabBar.waitForExistence(timeout: 45))
        try await fixture.waitForWear(outfitID: outfitID, expectedCount: 2)
        // Relaunch again after the first replay committed but lost its response.
        // Durable replay must reconcile that ID without another wear-stat increment.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.chromeTabBar.waitForExistence(timeout: 45))
        app.tapChromeTab("Closet")
        let look = app.buttons["closet.looks.open"].firstMatch
        XCTAssertTrue(look.waitForExistence(timeout: 30))
        look.tap()
        XCTAssertTrue(app.descendants(matching: .any)["outfitDetail.action.markWorn"].waitForExistence(timeout: 30))
        try await fixture.waitForWear(outfitID: outfitID, expectedCount: 2)
    }

    private func verifyMonthlyReview(in app: XCUIApplication) {
        // Home opens the last completed month. This run's newly recorded wear
        // is in the current month, so the prior-month count must stay zero.
        app.tapChromeTab("Home")
        let reviewCard = app.descendants(matching: .any)["home.monthlyReview"]
        reviewCard.scrollIntoView(in: app)
        XCTAssertTrue(
            reviewCard.waitForExistence(timeout: 20),
            "Monthly Review was not reachable from Home."
        )
        reviewCard.tap()
        XCTAssertTrue(app.navigationBars["Monthly Review"].waitForExistence(timeout: 20))
        let monthlyWearCount = app.staticTexts["monthlyReview.statValue.looks-worn"]
        XCTAssertTrue(
            monthlyWearCount.waitForExistence(timeout: 30),
            "Monthly Review did not load its recorded facts."
        )
        XCTAssertEqual(
            monthlyWearCount.label,
            "0",
            "The current month's wear must not appear in last month's review."
        )
    }

    private func deleteFixtureAccount(in app: XCUIApplication, fixture: Fixture) async throws {
        // The fixture is disposable and this is its only selected journey
        // test. Delete through the product UI, then prove the old JWT cannot
        // continue to read the owner endpoint.
        app.tapChromeTab("Profile")
        let privacy = app.descendants(matching: .any)["profile.privacyAndDataRow"]
        XCTAssertTrue(
            privacy.waitForExistence(timeout: 20),
            "Privacy & Data was not reachable from Profile."
        )
        privacy.tap()
        let deleteRow = app.descendants(matching: .any)["privacyAndData.deleteAccountRow"]
        XCTAssertTrue(
            deleteRow.waitForExistence(timeout: 20),
            "The account deletion route was not reachable."
        )
        deleteRow.tap()
        let acknowledge = app.descendants(matching: .any)["accountDeletion.acknowledgeToggle"]
        XCTAssertTrue(
            acknowledge.waitForExistence(timeout: 20),
            "The deletion acknowledgment control was missing."
        )
        acknowledge.tap()
        let delete = app.descendants(matching: .any)["accountDeletion.deleteButton"]
        XCTAssertTrue(
            delete.waitForExistence(timeout: 10),
            "The account deletion control was missing."
        )
        XCTAssertTrue(
            delete.isEnabled,
            "Acknowledging permanent deletion should enable the action."
        )
        delete.tap()
        let confirm = app.buttons["Delete Permanently"]
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 10),
            "The final deletion confirmation was not shown."
        )
        confirm.tap()
        let done = app.descendants(matching: .any)["accountDeletion.doneButton"]
        XCTAssertTrue(
            done.waitForExistence(timeout: 30),
            "The app did not confirm that account deletion started."
        )
        done.tap()
        XCTAssertTrue(
            app.buttons["Continue with Apple"].waitForExistence(timeout: 20),
            "Deletion did not return the app to sign-in."
        )
        try await fixture.waitUntilUnauthorized()
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

    private static func readFixture(at path: String) throws -> Fixture {
        let url = URL(fileURLWithPath: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard
            let size = attributes[.size] as? NSNumber,
            let permissions = attributes[.posixPermissions] as? NSNumber,
            size.intValue > 0,
            size.intValue <= 16_384,
            (permissions.intValue & 0o077) == 0
        else {
            throw XCTSkip("The local Kyra fixture must be a small owner-only file.")
        }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private static func isLoopbackHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme?.lowercased() == "http",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            return false
        }
        return ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased() ?? "")
    }

}

private struct Fixture: Decodable {
    let userID: UUID
    let accessToken: String
    let supabaseURL: String
    let supabaseAnonKey: String
    let itemNames: [String]
    let upstreamURL: String?
    let networkControlToken: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case accessToken = "access_token"
        case supabaseURL = "supabase_url"
        case supabaseAnonKey = "supabase_anon_key"
        case itemNames = "item_names"
        case upstreamURL = "upstream_url"
        case networkControlToken = "network_control_token"
    }

    func inject(_ id: String, method: String, path: String, mode: String = "503", count: Int = 1) async throws {
        _ = try await control(body: ["id": id, "method": method, "path": path, "mode": mode, "count": String(count)])
    }

    func verifyFaultsConsumed() async throws {
        let rules = try await control(body: nil)
        XCTAssertEqual(rules.count, 6)
        for rule in rules {
            if rule["mode"] as? String == "drop_after" {
                XCTAssertGreaterThanOrEqual(rule["requests"] as? Int ?? 0, 2,
                                            "The lost response must exercise a real retry.")
                XCTAssertTrue([200, 201, 204].contains(rule["upstream_status"] as? Int ?? 0),
                               "Lost-response test must discard a successful committed write.")
            }
            XCTAssertEqual(rule["injected"] as? Int, Int(rule["count"] as? String ?? "1"),
                           "The intended journey fault was not exercised: \(rule["id"] ?? "unknown")")
        }
    }

    private func control(body: [String: String]?) async throws -> [[String: Any]] {
        guard let token = networkControlToken,
              let url = URL(string: supabaseURL + "/__qa/faults"),
              url.host == "127.0.0.1" else { throw JourneyError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw JourneyError.requestFailed
        }
        return rules
    }

    func requestRows(table: String, query: String) async throws -> [[String: Any]] {
        var components = URLComponents(string: (upstreamURL ?? supabaseURL) + "/rest/v1/" + table)
        components?.percentEncodedQuery = query
        guard let url = components?.url else {
            throw JourneyError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw JourneyError.requestFailed
        }
        return rows
    }

    func waitForWear(outfitID: String, expectedCount: Int = 1) async throws {
        let ownerID = userID.uuidString.lowercased()
        let query = "select=id,user_id,outfit_id,worn_at&user_id=eq.\(ownerID)" +
            "&outfit_id=eq.\(outfitID)&order=worn_at.desc&limit=5"
        for _ in 0..<20 {
            if let wear = try await requestRows(table: "outfit_wears", query: query).first,
               wear["user_id"] as? String == ownerID,
               wear["outfit_id"] as? String == outfitID {
                let allWears = try await requestRows(table: "outfit_wears", query: query)
                if allWears.count < expectedCount {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                XCTAssertEqual(allWears.count, expectedCount, "Recovery must not duplicate the recorded wear.")
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw JourneyError.wearWasNotPersisted
    }

    func waitUntilUnauthorized() async throws {
        guard let url = URL(string: (upstreamURL ?? supabaseURL) + "/auth/v1/user") else {
            throw JourneyError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        for _ in 0..<60 {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JourneyError.requestFailed
            }
            if [401, 403].contains(httpResponse.statusCode) { return }
            guard httpResponse.statusCode == 200 else {
                throw JourneyError.requestFailed
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw JourneyError.accountDeletionDidNotRevokeAuth
    }
}

private enum JourneyError: Error {
    case invalidURL
    case requestFailed
    case wearWasNotPersisted
    case accountDeletionDidNotRevokeAuth
}
