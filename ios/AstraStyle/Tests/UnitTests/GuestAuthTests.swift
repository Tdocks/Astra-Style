//
//  GuestAuthTests.swift
//  AstraStyleTests
//
//  ADR 0018 anonymous trial: same uid across link, 10-item guest cap,
//  local photos never use a Storage path.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Anonymous auth trial")
struct GuestAuthTests {

    @Test("Guest closet cap is 10; signed-in free stays 30")
    func guestCapIsTen() {
        #expect(GuestLimits.maxClosetItems == 10)
        #expect(FreeTierLimits.maxClosetItems == 30)
    }

    @Test("Disabled anonymous provider maps to an honest Welcome sentence")
    func mapsAnonymousProviderDisabled() {
        let err = NSError(
            domain: "auth",
            code: 422,
            userInfo: [NSLocalizedDescriptionKey: "Anonymous sign-ins are disabled (anonymous_provider_disabled)"]
        )
        let mapped = LiveAuthRepository.anonymousSignInError(from: err)
        #expect(mapped.message.contains("Guest trial isn't turned on"))
    }

    @Test("Other anonymous failures stay generic")
    func mapsGenericAnonymousFailure() {
        let err = NSError(
            domain: "auth",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "network down"]
        )
        let mapped = LiveAuthRepository.anonymousSignInError(from: err)
        #expect(mapped.message.contains("Couldn't start a trial"))
    }

    @Test("Linking Apple keeps the anonymous user id")
    func linkKeepsUserID() async throws {
        let auth = MockAuthRepository(startSignedIn: false)
        let guest = try await auth.signInAnonymously()
        #expect(guest.isAnonymous)
        let linked = try await auth.linkAppleIdentity(identityToken: "token", nonce: "nonce")
        #expect(linked.userID == guest.userID)
        #expect(linked.isAnonymous == false)
    }

    @Test("The 11th guest item is refused")
    func eleventhGuestItemIsRefused() async throws {
        let userID = UUID()
        let base = MockClosetRepository(items: [])
        for index in 1...GuestLimits.maxClosetItems {
            _ = try await base.createItem(
                ClosetItem(id: UUID(), userID: userID, name: "G\(index)", category: .top),
                images: []
            )
        }
        let repository = FreeTierCappedClosetRepository(
            base: base,
            isEntitledToPremium: { false },
            isAnonymous: { true }
        )
        await #expect(throws: FreeTierClosetError.capReached(limit: GuestLimits.maxClosetItems)) {
            _ = try await repository.createItem(
                ClosetItem(id: UUID(), userID: userID, name: "G11", category: .top),
                images: []
            )
        }
    }

    @Test("Guest local paths never look like user-content")
    func guestPathsStayLocal() throws {
        let data = Data([0xFF, 0xD8, 0xFF])
        let path = try GuestLocalImageStore.save(data, userID: UUID())
        #expect(GuestLocalImageStore.isLocal(path))
        #expect(!path.hasPrefix("users/"))
        try GuestLocalImageStore.delete(path)
    }

    @Test("Guest transparent cutouts retain PNG filenames and bytes")
    func guestPNGBytesRoundTrip() throws {
        let data = Data([137, 80, 78, 71, 13, 10, 26, 10])
        let path = try GuestLocalImageStore.save(data, userID: UUID())
        defer { try? GuestLocalImageStore.delete(path) }
        #expect(path.hasSuffix(".png"))
        #expect(GuestLocalImageStore.jpegData(for: path) == data)
    }

    @Test("Migration finds a local cutout after its source is already remote")
    func migrationFindsCutoutOnly() {
        let owner = UUID()
        let path = "guest-local/\(owner.uuidString.lowercased())/cutout.png"
        let image = ClosetItemImage(id: UUID(), closetItemID: UUID(), imageType: .front,
                                    storagePath: "users/remote.jpg", backgroundRemovedPath: path)
        let fields = GuestImageMigrationPaths.localFields(for: image, ownerID: owner)
        #expect(fields.count == 1)
        #expect(fields.first?.0 == "background_removed_path")
        #expect(fields.first?.1 == path)
        #expect(GuestImageMigrationPaths.localFields(for: image, ownerID: UUID()).isEmpty)
    }

    @Test("Guest JPEG bytes round-trip for migration onto Storage")
    func guestBytesRoundTrip() throws {
        let data = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let path = try GuestLocalImageStore.save(data, userID: UUID())
        #expect(GuestLocalImageStore.jpegData(for: path) == data)
        try GuestLocalImageStore.delete(path)
        #expect(GuestLocalImageStore.jpegData(for: path) == nil)
    }
}

@Suite("Wardrobe graph picker")
struct WardrobeGraphTests {

    @Test("Women's empty copy does not demand a top, bottom, and shoes")
    func womensEmptyCopy() {
        let copy = WardrobeGraph.womenswear.emptyClosetAdvice
        #expect(!copy.lowercased().contains("top, bottom, and shoes"))
        #expect(copy.lowercased().contains("dress"))
    }

    @Test("A dress plus shoes completes the women's graph")
    func dressAndShoesComplete() {
        let missing = WardrobeGraph.womenswear.missingRoles(in: [.dress: 1, .shoes: 1])
        #expect(missing.isEmpty)
        let mens = WardrobeGraph.menswear3Role.missingRoles(in: [.dress: 1, .shoes: 1])
        #expect(mens.contains(.top))
        #expect(mens.contains(.bottom))
    }

    @Test("Home empty reason is keyed by graph")
    func homeEmptyReasonUsesGraph() {
        let data = HomeBriefData(
            greetingName: "Ada",
            weather: nil,
            schedule: nil,
            brief: DailyBrief(id: UUID(), userID: UUID(), briefDate: .now),
            primaryOutfit: nil,
            primaryOutfitItems: [],
            closetRoleCounts: [.dress: 3, .shoes: 2],
            wearableRoleCounts: [.dress: 3, .shoes: 2],
            wardrobeGraph: .womenswear
        )
        #expect(data.missingRoles.isEmpty)
        #expect(data.emptyReason == .noOutfitYet)
    }

    @Test("Home presentRoles names owned women's roles without inventing tops")
    func presentRolesForDressCloset() {
        let data = HomeBriefData(
            greetingName: "Ada",
            weather: nil,
            schedule: nil,
            brief: DailyBrief(id: UUID(), userID: UUID(), briefDate: .now),
            primaryOutfit: nil,
            primaryOutfitItems: [],
            closetRoleCounts: [.dress: 2, .shoes: 1],
            wearableRoleCounts: [.dress: 2, .shoes: 1],
            wardrobeGraph: .womenswear
        )
        #expect(Set(data.presentRoles) == Set([.dress, .shoes]))
        #expect(!data.presentRoles.contains(.top))
    }

    @Test("Women's quiz is its own manifest, not a copy of the men's pair ids")
    func womensQuizIsOwnManifest() {
        let locator = AlwaysResolvingImageLocator()
        let bundle = Bundle(for: LiveAuthRepository.self)
        let women = StyleQuizCatalog.bundled(for: .womenswear, bundle: bundle, locator: locator)
        let men = StyleQuizCatalog.bundled(for: .menswear3Role, bundle: bundle, locator: locator)
        #expect(!women.pairs.isEmpty)
        #expect(Set(women.pairs.map(\.id)).isDisjoint(with: Set(men.pairs.map(\.id))))
        #expect(women.pairs.allSatisfy { $0.id.hasPrefix("w-") })
    }
}
