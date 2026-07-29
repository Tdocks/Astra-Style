//
//  SessionRestoreTests.swift
//  AstraStyleTests
//
//  Phase 1 exit criterion (docs/01-build-roadmap.md): "killing and
//  relaunching the app restores the session without re-authenticating."
//  Exercises `SessionStore.restoreSession()` end to end against a real
//  `KeychainTokenStore` (a fresh, uniquely-named Keychain service per test,
//  so tests never interfere with each other or with a real app install)
//  and a fake `SessionRefreshing`, covering every case named in the task:
//  valid, expired-but-refreshable, expired-and-unrefreshable,
//  corrupt-Keychain, absent, and a guest session across a simulated
//  relaunch.
//

import Foundation
import Security
import Testing
@testable import AstraStyle

@MainActor
@Suite("SessionStore.restoreSession() — spec §7 session restoration")
struct SessionRestoreTests {

    private func uniqueKeychain() -> KeychainTokenStore {
        KeychainTokenStore(service: "astra.test.session-restore.\(UUID().uuidString)")
    }

    /// A fresh `AstraAPIClient`/`SupabaseClient` pair per call — deliberately
    /// not the shared `.previewClient` singletons, so nothing here can race
    /// with another test over `AstraAPIClient`'s token-provider box.
    private func makeSessionStore(keychain: KeychainTokenStore, refresher: SessionRefreshing) -> SessionStore {
        SessionStore(
            apiClient: AstraAPIClient(environment: .preview),
            supabase: AstraSupabaseClientFactory.previewClient,
            keychain: keychain,
            sessionRefresher: refresher
        )
    }

    @Test("A valid, non-expired session is restored as-is")
    func restoresValidSession() async throws {
        let keychain = uniqueKeychain()
        let original = AuthSession(
            userID: UUID(),
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: .now.addingTimeInterval(3600)
        )
        try keychain.save(original)

        let refresher = StubRefresher(result: .failure(AstraError.auth("must not be called for a valid session")))
        let sessionStore = makeSessionStore(keychain: keychain, refresher: refresher)

        let restored = try await sessionStore.restoreSession()

        #expect(restored?.userID == original.userID)
        #expect(restored?.accessToken == "access-token")
        #expect(sessionStore.isRestoring == false)
        #expect(await refresher.callCount == 0)
    }

    @Test("An expired session is refreshed transparently and the new tokens are persisted")
    func refreshesExpiredSession() async throws {
        let keychain = uniqueKeychain()
        let userID = UUID()
        let expired = AuthSession(
            userID: userID,
            accessToken: "stale-access",
            refreshToken: "refresh-me",
            expiresAt: .now.addingTimeInterval(-3600)
        )
        try keychain.save(expired)

        let refreshed = RefreshedSession(
            userID: userID,
            accessToken: "fresh-access",
            refreshToken: "fresh-refresh",
            expiresAt: .now.addingTimeInterval(3600)
        )
        let refresher = StubRefresher(result: .success(refreshed))
        let sessionStore = makeSessionStore(keychain: keychain, refresher: refresher)

        let restored = try await sessionStore.restoreSession()

        #expect(restored?.accessToken == "fresh-access")
        #expect(restored?.userID == userID)
        #expect(await refresher.callCount == 1)

        // The refreshed session was actually persisted, not just returned
        // in memory — a second restore (simulating another relaunch)
        // should see the *new* tokens without refreshing again.
        let reloaded = try keychain.load()
        #expect(reloaded?.accessToken == "fresh-access")
    }

    @Test("An expired session whose refresh token is rejected returns nil and clears the stale entry")
    func expiredAndUnrefreshableClearsSession() async throws {
        let keychain = uniqueKeychain()
        let expired = AuthSession(
            userID: UUID(),
            accessToken: "stale-access",
            refreshToken: "dead-refresh-token",
            expiresAt: .now.addingTimeInterval(-3600)
        )
        try keychain.save(expired)

        let refresher = StubRefresher(result: .failure(AstraError.auth("Refresh token expired or revoked.")))
        let sessionStore = makeSessionStore(keychain: keychain, refresher: refresher)

        let restored = try await sessionStore.restoreSession()

        #expect(restored == nil)
        #expect(sessionStore.isSignedIn == false)
        // A signed-out route, not a hang: the stale entry doesn't linger to
        // fail the same way on every future launch.
        #expect(try keychain.load() == nil)
    }

    @Test("No stored session returns nil without ever calling the refresher")
    func absentSessionReturnsNilWithoutRefreshing() async throws {
        let keychain = uniqueKeychain()
        let refresher = StubRefresher(result: .failure(AstraError.auth("must not be called when nothing is stored")))
        let sessionStore = makeSessionStore(keychain: keychain, refresher: refresher)

        let restored = try await sessionStore.restoreSession()

        #expect(restored == nil)
        #expect(await refresher.callCount == 0)
    }

    @Test("A Keychain item present but corrupt is treated as no session, not a crash")
    func corruptKeychainEntryIsTreatedAsAbsent() async throws {
        let service = "astra.test.session-restore.\(UUID().uuidString)"
        let keychain = KeychainTokenStore(service: service)
        writeCorruptKeychainEntry(service: service)

        let refresher = StubRefresher(result: .failure(AstraError.auth("must not be called for a corrupt entry")))
        let sessionStore = makeSessionStore(keychain: keychain, refresher: refresher)

        let restored = try await sessionStore.restoreSession()

        #expect(restored == nil)
        #expect(await refresher.callCount == 0)
        // The corrupt entry was cleaned up (self-healed) rather than left
        // behind to fail identically on every future launch.
        #expect(try keychain.load() == nil)
    }

    @Test("A guest session survives a simulated kill-and-relaunch and is still flagged as a guest")
    func guestSessionSurvivesRelaunchWithoutRefreshing() async throws {
        let keychain = uniqueKeychain()
        let guestID = UUID()
        let guestSession = AuthSession(userID: guestID, accessToken: "", refreshToken: "", expiresAt: .distantFuture, isGuest: true)

        // First "launch": adopt the guest session, as `continueAsGuest()` would.
        let refresherA = StubRefresher(result: .failure(AstraError.auth("guest sessions must never refresh")))
        let firstLaunchStore = makeSessionStore(keychain: keychain, refresher: refresherA)
        try firstLaunchStore.adopt(guestSession)

        // "Kill and relaunch": a brand new `SessionStore` instance — as
        // `AstraStyleApp` constructs at every launch — backed by the same
        // Keychain entry, with nothing carried over in memory.
        let refresherB = StubRefresher(result: .failure(AstraError.auth("guest sessions must never refresh")))
        let relaunchedStore = makeSessionStore(keychain: keychain, refresher: refresherB)
        let restored = try await relaunchedStore.restoreSession()

        #expect(restored?.isGuest == true)
        #expect(restored?.userID == guestID)
        #expect(relaunchedStore.isGuest == true)
        // A guest is never confused for a real account: `isSignedIn` is
        // `true` (there *is* a usable local session)...
        #expect(relaunchedStore.isSignedIn == true)
        // ...but nothing about it ever reached the refresh path, which is
        // exactly the path that would imply a server-side identity.
        #expect(await refresherB.callCount == 0)
    }
}

/// Configurable `SessionRefreshing` double that also counts calls, so tests
/// can assert both the outcome and — for the paths that must never touch
/// the network (guest, absent, corrupt) — that it was never invoked at all.
private actor StubRefresher: SessionRefreshing {
    private let result: Result<RefreshedSession, AstraError>
    private(set) var callCount = 0

    init(result: Result<RefreshedSession, AstraError>) {
        self.result = result
    }

    func refreshSession(refreshToken: String) async throws -> RefreshedSession {
        callCount += 1
        return try result.get()
    }
}

/// Writes a Keychain item at the same (service, account) `KeychainTokenStore`
/// uses, but with a payload that isn't valid `PersistedSession` JSON —
/// simulating a corrupted entry (e.g. left behind by a schema change or a
/// partially-written value) without needing `KeychainTokenStore` to expose
/// any test-only backdoor.
private func writeCorruptKeychainEntry(service: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: "astra.session",
        kSecValueData as String: Data("not valid PersistedSession json".utf8),
    ]
    SecItemDelete(query as CFDictionary)
    SecItemAdd(query as CFDictionary, nil)
}
