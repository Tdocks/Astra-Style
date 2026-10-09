import XCTest
@testable import AstraStyle

final class LiveClosetImageURLResolverOwnershipTests: XCTestCase {
    func testResolveRequiresAnAuthenticatedOwner() async {
        let resolver = makeResolver(currentUserID: { nil })
        let owner = UUID()
        let path = closetPath(ownerID: owner)

        do {
            _ = try await resolver.resolve(storagePath: path)
            XCTFail("A private image path must not resolve without a session.")
        } catch let error as AstraError {
            XCTAssertEqual(error.category, .auth)
        } catch {
            XCTFail("Expected an authentication error, received \(error)." )
        }
    }

    func testResolveRejectsAnotherAccountsGuestLocalPhoto() async throws {
        let owner = UUID()
        let peer = UUID()
        let path = try GuestLocalImageStore.save(
            Data([137, 80, 78, 71, 13, 10, 26, 10]),
            userID: peer
        )
        defer { try? GuestLocalImageStore.delete(path) }
        let resolver = makeResolver(currentUserID: { owner })

        do {
            _ = try await resolver.resolve(storagePath: path)
            XCTFail("A guest photo owned by a different account must not resolve.")
        } catch let error as AstraError {
            XCTAssertEqual(error.category, .auth)
        } catch {
            XCTFail("Expected an authentication error, received \(error)." )
        }
    }

    func testResolveRechecksOwnerAfterCacheLookupSuspends() async {
        let firstOwner = UUID()
        let nextOwner = UUID()
        let sequence = OwnerSequence([firstOwner, nextOwner])
        let resolver = makeResolver(currentUserID: { await sequence.next() })

        do {
            _ = try await resolver.resolve(storagePath: closetPath(ownerID: firstOwner))
            XCTFail("A session change during resolution must stop the lookup before signing.")
        } catch let error as AstraError {
            XCTAssertEqual(error.category, .auth)
        } catch {
            XCTFail("Expected an authentication error, received \(error)." )
        }
    }

    func testSharedPathRevisionInvalidatesSignaturesInEveryResolver() async throws {
        let owner = UUID()
        let path = "users/\(owner.uuidString.lowercased())/studio/\(UUID().uuidString.lowercased())/result.png"
        let signedURL = try XCTUnwrap(URL(string: "https://storage.example.test/private-image?signature=temporary"))
        let firstResolver = makeResolver(currentUserID: { owner })
        let secondResolver = makeResolver(currentUserID: { owner })
        let sharedCache = ClosetImageByteCache.shared
        await sharedCache.removeAll(ownerID: owner)
        let initialRevision = await sharedCache.invalidationRevision(ownerID: owner, storagePath: path)
        await firstResolver.store(signedURL, for: path, ownerID: owner, revision: initialRevision)
        await secondResolver.store(signedURL, for: path, ownerID: owner, revision: initialRevision)

        let firstHit = await firstResolver.usableCachedURL(for: path, ownerID: owner)
        let secondHit = await secondResolver.usableCachedURL(for: path, ownerID: owner)
        XCTAssertEqual(firstHit, signedURL)
        XCTAssertEqual(secondHit, signedURL)

        // This is the root repository hook: it only knows the shared cache,
        // not the individual resolver actor instances.
        await sharedCache.remove(ownerID: owner, storagePath: path)
        let firstMiss = await firstResolver.usableCachedURL(for: path, ownerID: owner)
        let secondMiss = await secondResolver.usableCachedURL(for: path, ownerID: owner)
        XCTAssertNil(firstMiss)
        XCTAssertNil(secondMiss)

        let postDeleteRevision = await sharedCache.invalidationRevision(ownerID: owner, storagePath: path)
        await firstResolver.store(signedURL, for: path, ownerID: owner, revision: postDeleteRevision)
        await secondResolver.store(signedURL, for: path, ownerID: owner, revision: postDeleteRevision)
        await sharedCache.removeAll(ownerID: owner)
        let firstOwnerPurgeMiss = await firstResolver.usableCachedURL(for: path, ownerID: owner)
        let secondOwnerPurgeMiss = await secondResolver.usableCachedURL(for: path, ownerID: owner)
        XCTAssertNil(firstOwnerPurgeMiss)
        XCTAssertNil(secondOwnerPurgeMiss)
    }

    private func makeResolver(currentUserID: @escaping @Sendable () async -> UUID?) -> LiveClosetImageURLResolver {
        LiveClosetImageURLResolver(
            apiClient: AstraAPIClient(environment: .preview),
            supabase: AstraSupabaseClientFactory.previewClient,
            currentUserID: currentUserID
        )
    }

    private func closetPath(ownerID: UUID) -> String {
        "users/\(ownerID.uuidString.lowercased())/closet/\(UUID().uuidString.lowercased()).jpg"
    }
}

private actor OwnerSequence {
    private var values: [UUID]

    init(_ values: [UUID]) {
        self.values = values
    }

    func next() -> UUID? {
        guard !values.isEmpty else { return nil }
        return values.removeFirst()
    }
}
