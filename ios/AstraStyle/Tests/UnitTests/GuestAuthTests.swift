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

    @Test("Wardrobe graph is not skippable")
    func pickerIsRequired() {
        #expect(!OnboardingStep.wardrobeGraph.isSkippable)
        #expect(OnboardingStep.firstRunSequence.contains(.wardrobeGraph))
        #expect(OnboardingStep.firstRunSequence.firstIndex(of: .wardrobeGraph)! <
                OnboardingStep.firstRunSequence.firstIndex(of: .identity)!)
    }
}
