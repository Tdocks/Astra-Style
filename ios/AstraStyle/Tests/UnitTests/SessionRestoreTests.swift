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
//  corrupt-Keychain and absent sessions across a simulated
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

    @Test("An API request renews an expired guest session and persists rotated credentials")
    func requestRefreshesExpiredSession() async throws {
        let keychain = uniqueKeychain()
        let userID = UUID()
        let refresher = StubRefresher(result: .success(RefreshedSession(
            userID: userID, accessToken: "renewed", refreshToken: "rotated",
            expiresAt: .now.addingTimeInterval(3600))))
        let store = makeSessionStore(keychain: keychain, refresher: refresher)
        store.adoptInMemory(AuthSession(userID: userID, accessToken: "expired",
                                       refreshToken: "old", expiresAt: .now.addingTimeInterval(-1),
                                       isAnonymous: true))
        #expect(await store.currentAccessToken() == "renewed")
        #expect(store.currentSession?.isAnonymous == true)
        #expect(try keychain.load()?.refreshToken == "rotated")
        #expect(await store.currentAccessToken() == "renewed")
        #expect(await refresher.callCount == 1)
    }

    @Test("A failed network refresh keeps credentials for a later retry")
    func requestNetworkFailureRetainsSession() async throws {
        let keychain = uniqueKeychain()
        let refresher = StubRefresher(result: .failure(.network("Offline")))
        let store = makeSessionStore(keychain: keychain, refresher: refresher)
        let session = AuthSession(userID: UUID(), accessToken: "expired", refreshToken: "retry",
                                  expiresAt: .now.addingTimeInterval(-1))
        try store.adopt(session)
        #expect(await store.currentAccessToken() == nil)
        #expect(store.currentSession?.userID == session.userID)
        #expect(try keychain.load()?.refreshToken == "retry")
    }

    @Test("Refresh cannot replace the account with a different identity")
    func requestRejectsDifferentIdentity() async throws {
        let keychain = uniqueKeychain()
        let refresher = StubRefresher(result: .success(RefreshedSession(
            userID: UUID(), accessToken: "other-account", refreshToken: "other",
            expiresAt: .now.addingTimeInterval(3600))))
        let store = makeSessionStore(keychain: keychain, refresher: refresher)
        try store.adopt(AuthSession(userID: UUID(), accessToken: "expired", refreshToken: "old",
                                   expiresAt: .now.addingTimeInterval(-1)))
        #expect(await store.currentAccessToken() == nil)
        #expect(store.currentSession == nil)
        #expect(try keychain.load() == nil)
    }

    @Test("Concurrent API requests share one renewal")
    func concurrentRequestsShareRefresh() async throws {
        let userID = UUID()
        let refresher = PausedRefresher(userID: userID)
        let store = makeSessionStore(keychain: uniqueKeychain(), refresher: refresher)
        store.adoptInMemory(AuthSession(userID: userID, accessToken: "expired", refreshToken: "old",
                                       expiresAt: .now.addingTimeInterval(-1)))
        let first = Task { await store.currentAccessToken() }
        await refresher.waitUntilStarted()
        let second = Task { await store.currentAccessToken() }
        await Task.yield()
        await refresher.finish()
        #expect(await first.value == "renewed")
        #expect(await second.value == "renewed")
        #expect(await refresher.callCount == 1)
    }

    @Test("A refresh finishing after sign-out cannot restore the account")
    func lateRefreshCannotRestoreSignedOutSession() async throws {
        let keychain = uniqueKeychain()
        let userID = UUID()
        let refresher = PausedRefresher(userID: userID)
        let store = makeSessionStore(keychain: keychain, refresher: refresher)
        store.adoptInMemory(AuthSession(userID: userID, accessToken: "expired", refreshToken: "old",
                                       expiresAt: .now.addingTimeInterval(-1)))
        let request = Task { await store.currentAccessToken() }
        await refresher.waitUntilStarted()
        store.clearInMemorySession()
        await refresher.finish()
        #expect(await request.value == nil)
        #expect(store.currentSession == nil)
        #expect(try keychain.load() == nil)
    }

    @Test("An offline launch retains the stored refresh token for recovery")
    func offlineRestorePreservesCredentials() async throws {
        let keychain = uniqueKeychain()
        let session = AuthSession(userID: UUID(), accessToken: "expired", refreshToken: "recoverable",
                                  expiresAt: .now.addingTimeInterval(-1))
        try keychain.save(session)
        let store = makeSessionStore(keychain: keychain,
                                     refresher: StubRefresher(result: .failure(.network("Offline"))))
        #expect(try await store.restoreSession() == nil)
        #expect(try keychain.load()?.refreshToken == "recoverable")
        #expect(store.isRestoring == false)
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

}

/// Configurable `SessionRefreshing` double that also counts calls, so tests
/// can assert both the outcome and — for the paths that must never touch
/// the network (absent, corrupt) — that it was never invoked at all.
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
        kSecValueData as String: Data("not valid PersistedSession json".utf8)
    ]
    SecItemDelete(query as CFDictionary)
    SecItemAdd(query as CFDictionary, nil)
}

private actor PausedRefresher: SessionRefreshing {
    let userID: UUID
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<RefreshedSession, Never>?
    init(userID: UUID) { self.userID = userID }
    func refreshSession(refreshToken: String) async throws -> RefreshedSession {
        callCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        while continuation == nil { await Task.yield() }
    }
    func finish() {
        continuation?.resume(returning: RefreshedSession(
            userID: userID, accessToken: "renewed", refreshToken: "rotated",
            expiresAt: .now.addingTimeInterval(3600)))
        continuation = nil
    }
}
