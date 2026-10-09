import Foundation
import Testing
@testable import AstraStyle

@Suite("Shop the Look")
@MainActor
struct ShopTheLookViewModelTests {
    @Test("loads only the signed-in owner's saved outfit pieces")
    func loadsOwnedLook() async {
        let model = ShopTheLookViewModel(
            outfitID: SampleData.heroOutfit.id,
            outfitRepository: MockOutfitRepository(),
            closetRepository: MockClosetRepository(),
            profileRepository: MockProfileRepository(),
            shoppingRepository: MockShoppingRepository(),
            imageURLResolver: MockClosetImageURLResolver(),
            currentOwnerID: { SampleData.profile.id }
        )

        await model.onAppear()

        guard case .loaded(let look) = model.state else {
            Issue.record("Expected the seeded owner outfit to load")
            return
        }
        #expect(look.outfit.id == SampleData.heroOutfit.id)
        #expect(!look.ownedPieces.isEmpty)
        #expect(look.missingPieces.isEmpty)
    }

    @Test("rejects another owner's outfit before building a shopping view")
    func rejectsPeerOutfit() async {
        let stranger = Profile(id: UUID())
        let model = ShopTheLookViewModel(
            outfitID: SampleData.heroOutfit.id,
            outfitRepository: MockOutfitRepository(),
            closetRepository: MockClosetRepository(),
            profileRepository: MockProfileRepository(profile: stranger),
            shoppingRepository: MockShoppingRepository(),
            imageURLResolver: MockClosetImageURLResolver(),
            currentOwnerID: { stranger.id }
        )

        await model.onAppear()

        if case .loaded = model.state {
            Issue.record("A peer outfit must not reach the Shop the Look surface")
        }
    }

    @Test("never presents a candidate as the wrong outfit role")
    func mismatchedCandidateIsRejected() {
        let candidate = ProductCandidate(
            id: UUID(),
            canonicalURL: URL(string: "https://example.com/item") ?? URL(fileURLWithPath: "/"),
            name: "Test boot",
            category: .shoes
        )

        #expect(ShopTheLookPresentation.candidate(candidate, matches: .top) == nil)
        #expect(ShopTheLookPresentation.candidate(candidate, matches: .shoes) == candidate)
    }

    @Test("creates missing-product cards only from explicit product candidate references")
    func missingItemsRequireCandidateIDs() {
        let outfitID = UUID()
        let candidateID = UUID()
        let candidate = ProductCandidate(
            id: candidateID,
            canonicalURL: URL(string: "https://example.com/item") ?? URL(fileURLWithPath: "/"),
            name: "Test shoe",
            category: .shoes
        )
        let rows = [
            OutfitItem(outfitID: outfitID, role: .top, sortOrder: 0),
            OutfitItem(outfitID: outfitID, productCandidateID: candidateID, role: .shoes, sortOrder: 1),
            OutfitItem(outfitID: outfitID, closetItemID: UUID(), role: .bottom, sortOrder: 2)
        ]

        let missing = ShopTheLookPresentation.missingPieces(
            from: rows,
            candidatesByID: [candidateID: candidate]
        )

        #expect(missing.count == 1)
        #expect(missing.first?.candidate == candidate)
        #expect(missing.first?.role == .shoes)
    }

    @Test("shows only explicitly supplied sizes and a truthful affiliate disclosure")
    func productDisclosureAndSizes() {
        let affiliateCandidate = ProductCandidate(
            id: UUID(),
            canonicalURL: URL(string: "https://example.com/item") ?? URL(fileURLWithPath: "/"),
            name: "Test boot",
            category: .shoes,
            affiliateURL: URL(string: "https://example.com/affiliate")
        )
        let sizesCandidate = ProductCandidate(
            id: affiliateCandidate.id,
            canonicalURL: affiliateCandidate.canonicalURL,
            name: affiliateCandidate.name,
            category: .shoes,
            affiliateURL: affiliateCandidate.affiliateURL,
            availability: .object(["sizes": .array([.string(" 8 "), .number(9), .string(""), .string("10")])])
        )
        let nonAffiliateCandidate = ProductCandidate(
            id: UUID(),
            canonicalURL: affiliateCandidate.canonicalURL,
            name: "Test boot",
            category: .shoes
        )

        #expect(ShopTheLookPresentation.availableSizes(from: sizesCandidate) == ["8", "10"])
        #expect(ShopTheLookPresentation.affiliateDisclosure(for: affiliateCandidate).contains("may earn a commission"))
        #expect(ShopTheLookPresentation.affiliateDisclosure(for: nonAffiliateCandidate).contains("No affiliate link"))
        #expect(ShopTheLookPresentation.affiliateDisclosure(for: nil).contains("unavailable"))
    }
}
