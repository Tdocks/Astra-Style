import Foundation
import Testing
@testable import AstraStyle

@Suite("Discover editorial config")
struct DiscoverEditorialRepositoryTests {
    @Test("Config controls guide order, publication, and brand metadata")
    func configFiltersAndOrdersEditorialEntries() throws {
        let decoded = try decodeEntries([
            entry(id: "second", order: 20, kind: "seasonal_guide"),
            entry(id: "draft", order: 1, kind: "fit_guide", isPublished: false),
            entry(
                id: "brand",
                order: 2,
                kind: "brand_spotlight",
                editorialLabel: "Editorial · Not sponsored",
                isSponsored: false,
                reviewedAt: reviewedAt,
                sources: [officialSource]
            ),
            entry(id: "first", order: 10, kind: "style_education")
        ])

        #expect(decoded.map(\.id) == ["brand", "first", "second"])
        let brand = try #require(decoded.first(where: { $0.kind == .brandSpotlight }))
        #expect(brand.editorialLabel == "Editorial · Not sponsored")
        #expect(brand.sources?.first?.destination?.host == "example.com")
    }

    @Test("Brand profiles require source links, review date, and visible editorial label")
    func brandProfilesFailClosedWithoutAttributionAndDisclosure() throws {
        let invalidEntries = [
            entry(
                id: "no-label",
                order: 1,
                kind: "brand_spotlight",
                isSponsored: false,
                reviewedAt: reviewedAt,
                sources: [officialSource]
            ),
            entry(
                id: "paid-without-label",
                order: 2,
                kind: "brand_spotlight",
                isSponsored: true,
                reviewedAt: reviewedAt,
                sources: [officialSource]
            ),
            entry(
                id: "bad-source",
                order: 3,
                kind: "brand_spotlight",
                editorialLabel: "Editorial · Not sponsored",
                isSponsored: false,
                reviewedAt: reviewedAt,
                sources: [DiscoverGuideSource(title: "Unsafe", url: "javascript:alert(1)")]
            )
        ]

        #expect(try decodeEntries(invalidEntries).isEmpty)
    }

    @Test("Sponsored content of every kind requires a visible disclosure")
    func sponsorshipDisclosureAppliesAcrossKinds() throws {
        let hiddenSponsored = entry(
            id: "sponsored-style-no-label",
            order: 1,
            kind: "style_education",
            isSponsored: true
        )
        #expect(try decodeEntries([hiddenSponsored]).isEmpty)

        let labeledSponsored = entry(
            id: "sponsored-style",
            order: 1,
            kind: "style_education",
            isSponsored: true,
            sponsorshipDisclosure: "Sponsored by Example Co."
        )
        let decoded = try decodeEntries([labeledSponsored])
        #expect(decoded.first?.visibleCommercialLabel == "Sponsored by Example Co.")
    }

    @Test("Paid brand content publishes its visible sponsorship disclosure")
    func sponsoredBrandCanPublishWithDisclosure() throws {
        let sponsoredBrand = entry(
            id: "sponsored",
            order: 1,
            kind: "brand_spotlight",
            isSponsored: true,
            sponsorshipDisclosure: "Sponsored by Example Co.",
            reviewedAt: reviewedAt,
            sources: [officialSource]
        )

        let decoded = try decodeEntries([sponsoredBrand])
        #expect(decoded.first?.visibleCommercialLabel == "Sponsored by Example Co.")
    }
}

private let reviewedAt = "2026-10-09T12:00:00Z"
private let officialSource = DiscoverGuideSource(
    title: "Official about page",
    url: "https://example.com/about"
)

private func decodeEntries(_ entries: [[String: Any]]) throws -> [DiscoverGuide] {
    let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "entries": entries])
    return try BundleDiscoverEditorialRepository.decodeCatalog(data)
}

private func entry(
    id: String,
    order: Int,
    kind: String,
    isPublished: Bool = true,
    editorialLabel: String? = nil,
    isSponsored: Bool? = nil,
    sponsorshipDisclosure: String? = nil,
    reviewedAt: String? = nil,
    sources: [DiscoverGuideSource]? = nil
) -> [String: Any] {
    var result: [String: Any] = [
        "id": id,
        "sortOrder": order,
        "kind": kind,
        "title": "Guide \(id)",
        "summary": "An original practical guide.",
        "readingMinutes": 3,
        "sections": [["heading": "Try this", "body": "Make one small adjustment."]],
        "isPublished": isPublished
    ]
    if let editorialLabel { result["editorialLabel"] = editorialLabel }
    if let isSponsored { result["isSponsored"] = isSponsored }
    if let sponsorshipDisclosure { result["sponsorshipDisclosure"] = sponsorshipDisclosure }
    if let reviewedAt { result["reviewedAt"] = reviewedAt }
    if let sources {
        result["sources"] = sources.map { ["title": $0.title, "url": $0.url] }
    }
    return result
}
