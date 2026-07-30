//
//  GuestModeNetworkTests.swift
//  AstraStyleTests
//
//  Phase 1 exit criterion (docs/01-build-roadmap.md): "A user can enter
//  guest mode ... without a network call." Proves `continueAsGuest()` never
//  reaches an Edge Function by routing `AstraAPIClient` through a
//  `URLProtocol` that fails loudly (and records) any request it sees.
//
//  This does not — and cannot, without assuming undocumented internals of
//  the `supabase-swift` package's own networking — also intercept a raw
//  `SupabaseClient` Postgrest/Auth/Storage call made independently of
//  `AstraAPIClient`. That half of the guarantee is structural instead:
//  `GuestClosetRepository` (Core/Persistence) has no `SupabaseClient` or
//  `AstraAPIClient` typed dependency at all, so there is literally no
//  HTTP-capable property for a future change to wire up by mistake — see
//  its doc comment. Reading `LiveAuthRepository.continueAsGuest()` confirms
//  the same for guest sign-in itself: it only calls `sessionStore.adopt`,
//  which only calls `KeychainTokenStore.save` — no `supabase.*` call
//  anywhere in the path.
//

import Foundation
import Testing
@testable import AstraStyle

// `SessionStore`'s initializer is `@MainActor`-isolated (the whole class
// is), so constructing one requires this suite to run on the main actor
// too — matching the pattern `Tests/UnitTests/SliceViewModelTests.swift`
// already established for the same reason.
@MainActor
@Suite("Guest mode makes zero network calls (spec §6.2)")
struct GuestModeNetworkTests {

    @Test("continueAsGuest() never sends a request through AstraAPIClient")
    func continueAsGuestMakesNoNetworkCalls() async throws {
        NetworkTrapURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkTrapURLProtocol.self]
        let trapSession = URLSession(configuration: configuration)

        let apiClient = AstraAPIClient(environment: .preview, session: trapSession)
        let sessionStore = SessionStore(
            apiClient: apiClient,
            supabase: AstraSupabaseClientFactory.previewClient,
            keychain: KeychainTokenStore(service: "astra.test.guest-network.\(UUID().uuidString)")
        )
        let authRepository = LiveAuthRepository(
            apiClient: apiClient,
            sessionStore: sessionStore,
            supabase: AstraSupabaseClientFactory.previewClient
        )

        let session = try await authRepository.continueAsGuest()

        #expect(session.isGuest)
        #expect(NetworkTrapURLProtocol.interceptedRequestCount == 0)
    }

    @Test("A guest closet write goes through GuestClosetRepository, which has no HTTP-capable dependency to misuse")
    func guestClosetRepositoryCannotReachNetworkByConstruction() async throws {
        // Compiles only because `GuestClosetRepository.init` takes a
        // `GuestClosetStore` (pure local storage) and a plain closure — if
        // a future edit tried to thread an `AstraAPIClient` or
        // `SupabaseClient` through here to "fix" some feature, it would
        // have to change the type's public initializer to do it, which is
        // a visible, reviewable diff rather than a silent regression.
        let guestID = UUID()
        let repository = GuestClosetRepository(store: InMemoryGuestClosetStore(), currentGuestUserID: { guestID })

        let created = try await repository.createItem(
            ClosetItem(id: UUID(), userID: UUID(), name: "Cotton Oxford", category: .top),
            images: []
        )

        #expect(created.userID == guestID)
    }
}

/// A `URLProtocol` that fails any request it's asked to handle and records
/// it, so a test can assert "nothing was ever sent" rather than merely
/// "nothing succeeded". Registered only on a dedicated
/// `URLSessionConfiguration` per test (never process-wide), so it can never
/// affect any other test running in parallel.
final class NetworkTrapURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _interceptedRequests: [URLRequest] = []

    static var interceptedRequestCount: Int {
        lock.withLock { _interceptedRequests.count }
    }

    static func reset() {
        lock.withLock { _interceptedRequests = [] }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self._interceptedRequests.append(request) }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
