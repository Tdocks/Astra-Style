import Foundation

/// Synthetic, non-network fixture selected only by an explicit UI-test launch argument.
enum ShopTheLookUITestFixture {
    static let candidateID = UUID(uuidString: "00000000-0000-4000-8000-000000000621") ?? UUID()

    static let outfit = Outfit(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000622") ?? UUID(),
        userID: SampleData.userID,
        name: "Shop the Look UI Fixture",
        description: "Synthetic saved outfit for Shop the Look UI acceptance.",
        formalityScore: 58,
        compatibilityScore: 92,
        source: .userCreated,
        createdAt: Date(timeIntervalSince1970: 4_102_444_800)
    )

    static let candidate = ProductCandidate(
        id: candidateID,
        canonicalURL: URL(string: "https://example.test/wool-overshirt") ?? URL(fileURLWithPath: "/"),
        retailer: "Fixture Outfit Goods",
        brand: "Fixture Outfit Goods",
        name: "Test Wool Overshirt",
        category: .outerwear,
        price: 180,
        currency: "USD",
        affiliateURL: URL(string: "https://example.test/affiliate/wool-overshirt") ?? URL(fileURLWithPath: "/"),
        availability: .object([
            "sizes": .array([.string("XS"), .string("M"), .string("XL")])
        ]),
        sponsored: true
    )
}
