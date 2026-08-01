//
//  ClosetFiltersTests.swift
//  AstraStyleTests
//
//  Spec §6.14 "Closet overview" — the filter panel, whose facet list the
//  spec gives verbatim: "Category. Color. Season. Brand. Condition. Fit.
//  Availability. Wear frequency."
//
//  P3-CLOSET-05's two acceptance criteria are both here, and the first one
//  is written as literally as it is stated:
//
//    "Combining 2+ filters (e.g. category=Tops, color=Blue) returns the
//     correct intersected result set against a fixture closet."
//
//  `intersectionOfCategoryAndColour` is that sentence. The fixture closet
//  it runs against deliberately holds a blue top, a blue garment that is
//  not a top, and a top that is not blue, so the three wrong answers are
//  all distinguishable: the union returns three, either facet on its own
//  returns two, and only the intersection returns one.
//
//    "Clearing filters returns to the unfiltered view without a full
//     screen reload flash."
//
//  A flash is not a thing a unit test can see, so what is asserted is the
//  property that makes one impossible: `apply(to:)` with nothing active
//  returns the array it was handed, unchanged and in order, so there is
//  nothing for the screen to reload. See `clearingRestoresTheOriginalArray`.
//
//  THE DECISIONS THAT ARE PINNED HERE RATHER THAN LEFT TO DRIFT.
//  Two of this feature's judgement calls are invisible in the code once
//  written and would be easy to reverse by accident, so each has a test
//  named for the behaviour AND the reason:
//
//  * values within one facet are ORed while facets are ANDed
//    (`orWithinAFacet`, `threeFacetsCompose`), and
//  * a garment with nothing recorded in a filtered field is EXCLUDED
//    (`nilFieldsAreExcludedNotWavedThrough`).
//
//  Wear-related assertions all pass an explicit `asOf:`, because the
//  recency windows are relative and a suite that used the wall clock would
//  pass or fail depending on when it ran.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("ClosetFilters — spec §6.14 closet filters")
struct ClosetFiltersTests {

    // MARK: - Fixtures

    /// A fixed instant, so every wear-recency window is deterministic.
    private static let reference = Date(timeIntervalSince1970: 1_750_000_000)

    private func daysAgo(_ days: Int) -> Date {
        Self.reference.addingTimeInterval(TimeInterval(-days * 86_400))
    }

    private func makeItem(
        name: String,
        category: ClothingCategory,
        color: String? = nil,
        secondaryColors: [String] = [],
        brand: String? = nil,
        seasons: [Season] = [],
        condition: ItemCondition? = nil,
        fit: ItemFit? = nil,
        availability: AvailabilityState = .available,
        wearCount: Int = 0,
        lastWornAt: Date? = nil,
        archivedAt: Date? = nil
    ) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: name,
            brand: brand,
            category: category,
            primaryColor: color,
            secondaryColors: secondaryColors,
            fit: fit,
            condition: condition,
            seasonality: seasons,
            wearCount: wearCount,
            lastWornAt: lastWornAt,
            availabilityState: availability,
            archivedAt: archivedAt
        )
    }

    /// The fixture closet the acceptance criteria are checked against.
    ///
    /// Six garments chosen so that no two facets select the same set: a
    /// blue top, a top that is not blue, a blue garment that is not a top,
    /// and three more that make the other five facets separable. The last
    /// one has nothing recorded in any optional field, which is what the
    /// exclusion rule is asserted against.
    private func makeCloset() -> [ClosetItem] {
        [
            makeItem(name: "Blue oxford shirt", category: .top, color: "Blue", brand: "A.P.C.",
                     seasons: [.spring, .summer], condition: .good, fit: .tailored,
                     wearCount: 12, lastWornAt: daysAgo(5)),
            makeItem(name: "White tee", category: .top, color: "White", brand: "apc",
                     seasons: [.summer], condition: .likeNew, fit: .regular,
                     wearCount: 3, lastWornAt: daysAgo(40)),
            makeItem(name: "Blue jeans", category: .bottom, color: "Blue", brand: "Levi's",
                     seasons: [.allSeason], condition: .worn, fit: .slim, availability: .inLaundry,
                     wearCount: 30, lastWornAt: daysAgo(2)),
            makeItem(name: "Green chore coat", category: .outerwear, color: "Green", brand: "Uniqlo",
                     seasons: [.fall], condition: .good, fit: .relaxed),
            makeItem(name: "Tan loafers", category: .shoes, color: "Tan", brand: "Alden",
                     seasons: [.allSeason], condition: .fair, wearCount: 8, lastWornAt: daysAgo(200)),
            makeItem(name: "Unrecorded belt", category: .accessory)
        ]
    }

    private func names(_ items: [ClosetItem]) -> [String] {
        items.map(\.name)
    }
}

// MARK: - The acceptance criteria

extension ClosetFiltersTests {

    @Test("Category and colour together return the garments that are BOTH, not the garments that are either — the union would return three of these six and each facet alone returns two")
    func intersectionOfCategoryAndColour() throws {
        let closet = makeCloset()
        let blue = try #require(ClosetFilterText.key("Blue"))

        var categoryOnly = ClosetFilters()
        categoryOnly.categories = [.top]
        #expect(names(categoryOnly.apply(to: closet)) == ["Blue oxford shirt", "White tee"])

        var colourOnly = ClosetFilters()
        colourOnly.colors = [blue]
        #expect(names(colourOnly.apply(to: closet)) == ["Blue oxford shirt", "Blue jeans"])

        var both = ClosetFilters()
        both.categories = [.top]
        both.colors = [blue]
        #expect(names(both.apply(to: closet)) == ["Blue oxford shirt"])
    }

    @Test("Two values in ONE facet are alternatives, not conditions — asking for tops and bottoms returns both, where an AND reading would return nothing and make every multi-select in the panel useless")
    func orWithinAFacet() {
        let closet = makeCloset()

        var filters = ClosetFilters()
        filters.categories = [.top, .bottom]

        #expect(names(filters.apply(to: closet)) == ["Blue oxford shirt", "White tee", "Blue jeans"])
    }

    @Test("Three facets narrow cumulatively, each one able to remove a garment the previous two kept")
    func threeFacetsCompose() {
        let closet = makeCloset()

        var filters = ClosetFilters()
        filters.categories = [.top]
        #expect(names(filters.apply(to: closet)) == ["Blue oxford shirt", "White tee"])

        filters.seasons = [.summer]
        #expect(names(filters.apply(to: closet)) == ["Blue oxford shirt", "White tee"])

        // The white tee is `likeNew`, so this third facet is what separates
        // two garments the first two could not.
        filters.conditions = [.good]
        #expect(names(filters.apply(to: closet)) == ["Blue oxford shirt"])
        #expect(filters.activeFacetCount == 3)
    }

    @Test("Clearing returns the closet exactly as it was — the same garments in the same order, which is what makes returning to the unfiltered view a no-op rather than a reload")
    func clearingRestoresTheOriginalArray() {
        let closet = makeCloset()

        var filters = ClosetFilters()
        filters.categories = [.top]
        filters.brands = ["alden"]
        #expect(filters.apply(to: closet).isEmpty)

        filters.clear()

        #expect(filters.isEmpty)
        #expect(filters.activeFacetCount == 0)
        // Element for element, in order. Nothing was rebuilt, reordered or
        // re-derived, so the screen has nothing to reload.
        #expect(filters.apply(to: closet) == closet)
    }

    @Test("An untouched filter set returns the whole closet rather than an empty one, so a panel nobody has used cannot blank the screen behind it")
    func noFiltersReturnsEverything() {
        let closet = makeCloset()
        #expect(ClosetFilters().apply(to: closet) == closet)
    }
}

// MARK: - Each of the eight facets on its own

extension ClosetFiltersTests {

    @Test("Category alone narrows to that category, the one facet that can never exclude a garment for having nothing on file")
    func categoryFacetAlone() {
        var filters = ClosetFilters()
        filters.categories = [.shoes]
        #expect(names(filters.apply(to: makeCloset())) == ["Tan loafers"])
    }

    @Test("Colour alone matches on the folded colour word, so the chip a user taps and the word stored on the garment need not be spelled identically")
    func colourFacetAlone() throws {
        var filters = ClosetFilters()
        filters.colors = [try #require(ClosetFilterText.key("  GREEN "))]
        #expect(names(filters.apply(to: makeCloset())) == ["Green chore coat"])
    }

    @Test("Season alone matches the tags actually on the garment")
    func seasonFacetAlone() {
        var filters = ClosetFilters()
        filters.seasons = [.fall]
        #expect(names(filters.apply(to: makeCloset())) == ["Green chore coat"])
    }

    @Test("Brand alone narrows to one label")
    func brandFacetAlone() throws {
        var filters = ClosetFilters()
        filters.brands = [try #require(ClosetFilterText.key("Levi's"))]
        #expect(names(filters.apply(to: makeCloset())) == ["Blue jeans"])
    }

    @Test("Condition alone narrows to garments in that condition")
    func conditionFacetAlone() {
        var filters = ClosetFilters()
        filters.conditions = [.fair]
        #expect(names(filters.apply(to: makeCloset())) == ["Tan loafers"])
    }

    @Test("Cut alone narrows to garments cut that way — a fact about the garment, not about the person wearing it")
    func fitFacetAlone() {
        var filters = ClosetFilters()
        filters.fits = [.slim]
        #expect(names(filters.apply(to: makeCloset())) == ["Blue jeans"])
    }

    @Test("Availability alone narrows to garments in that state, which is the facet that answers what can be worn today")
    func availabilityFacetAlone() {
        var filters = ClosetFilters()
        filters.availability = [.inLaundry]
        #expect(names(filters.apply(to: makeCloset())) == ["Blue jeans"])
    }

    @Test("Wear counts narrow by how many times a piece has been worn, and the bands are contiguous so a garment is always in exactly one")
    func wearCountFacetAlone() {
        let closet = makeCloset()

        var tenOrMore = ClosetFilters()
        tenOrMore.wearCounts = [.tenOrMore]
        #expect(names(tenOrMore.apply(to: closet, asOf: Self.reference)) == ["Blue oxford shirt", "Blue jeans"])

        var neverWorn = ClosetFilters()
        neverWorn.wearCounts = [.notWornYet]
        #expect(names(neverWorn.apply(to: closet, asOf: Self.reference)) == ["Green chore coat", "Unrecorded belt"])
    }

    @Test("Wear recency narrows by when a piece was last worn — the axis a count cannot supply, since twenty wears over five years and twenty since March are the same number and opposite facts")
    func wearRecencyFacetAlone() {
        let closet = makeCloset()

        var recent = ClosetFilters()
        recent.wearRecency = [.withinMonth]
        #expect(names(recent.apply(to: closet, asOf: Self.reference)) == ["Blue oxford shirt", "Blue jeans"])

        var stale = ClosetFilters()
        stale.wearRecency = [.longerAgo]
        #expect(names(stale.apply(to: closet, asOf: Self.reference)) == ["Tan loafers"])
    }

    @Test("The two wear axes are ANDed with each other, so a heavily worn piece that has been left alone for months is reachable and a heavily worn piece worn yesterday is not")
    func wearAxesCompose() {
        var filters = ClosetFilters()
        filters.wearCounts = [.tenOrMore]
        filters.wearRecency = [.withinMonth]

        #expect(names(filters.apply(to: makeCloset(), asOf: Self.reference)) == ["Blue oxford shirt", "Blue jeans"])

        filters.wearRecency = [.longerAgo]
        #expect(filters.apply(to: makeCloset(), asOf: Self.reference).isEmpty)
    }
}

// MARK: - The rules that are easy to reverse by accident

extension ClosetFiltersTests {

    @Test("A garment with nothing recorded in a filtered field is left out rather than waved through, because a filter for one brand that also returned every unbranded piece would read as a broken filter")
    func nilFieldsAreExcludedNotWavedThrough() {
        let closet = makeCloset()

        // "Unrecorded belt" carries no brand, colour, condition, fit or
        // season. Each of these four facets must drop it.
        var brand = ClosetFilters()
        brand.brands = ["apc"]
        #expect(names(brand.apply(to: closet)).contains("Unrecorded belt") == false)

        var condition = ClosetFilters()
        condition.conditions = [.good, .likeNew, .fair, .worn, .newWithTags]
        #expect(names(condition.apply(to: closet)).contains("Unrecorded belt") == false)

        var fit = ClosetFilters()
        fit.fits = Set(ItemFit.allCases)
        #expect(names(fit.apply(to: closet)).contains("Unrecorded belt") == false)

        var season = ClosetFilters()
        season.seasons = Set(Season.allCases)
        #expect(names(season.apply(to: closet)).contains("Unrecorded belt") == false)

        var colour = ClosetFilters()
        colour.colors = ["blue", "white", "green", "tan"]
        #expect(names(colour.apply(to: closet)).contains("Unrecorded belt") == false)

        // And the belt is genuinely in the closet — it is the filters that
        // exclude it, not the fixture that omits it.
        #expect(names(ClosetFilters().apply(to: closet)).contains("Unrecorded belt"))
    }

    @Test("A filter value nothing matches returns nothing, rather than falling back to the whole closet — an unmatched facet must narrow to empty, never widen")
    func aValueNothingMatchesReturnsNothing() {
        var filters = ClosetFilters()
        filters.colors = ["purple"]

        #expect(filters.apply(to: makeCloset()).isEmpty)
    }

    @Test("Brand matching ignores case, spacing, punctuation and accents, so one label recorded three ways is still one label")
    func brandMatchingIgnoresCaseSpacingAndPunctuation() throws {
        let closet = [
            makeItem(name: "Blazer", category: .outerwear, brand: "A.P.C."),
            makeItem(name: "Cardigan", category: .top, brand: "apc"),
            makeItem(name: "Trousers", category: .bottom, brand: " A P C "),
            makeItem(name: "Scarf", category: .accessory, brand: "Acne Studios")
        ]

        var filters = ClosetFilters()
        filters.brands = [try #require(ClosetFilterText.key("A.P.C."))]

        #expect(names(filters.apply(to: closet)) == ["Blazer", "Cardigan", "Trousers"])
    }

    @Test("A brand recorded as whitespace is not a brand, so it can never be matched or offered as a value")
    func whitespaceIsNotABrand() {
        #expect(ClosetFilterText.key("   ") == nil)
        #expect(ClosetFilterText.key(nil) == nil)
        #expect(ClosetFilterText.key("-") == nil)
    }

    @Test("A colour filter matches a secondary colour too, because the man who asks for blue wants the shirt with the blue stripe in it")
    func secondaryColoursMatch() {
        let closet = [
            makeItem(name: "Cream shirt with blue stripe", category: .top, color: "Cream", secondaryColors: ["Blue"]),
            makeItem(name: "Cream shirt", category: .top, color: "Cream")
        ]

        var filters = ClosetFilters()
        filters.colors = ["blue"]

        #expect(names(filters.apply(to: closet)) == ["Cream shirt with blue stripe"])
    }

    @Test("A colour word this build has no swatch for still filters, because the colour vocabulary is the user's and was never closed")
    func unknownColourWordStillFilters() throws {
        let closet = [
            makeItem(name: "Odd jacket", category: .outerwear, color: "Burnt sienna"),
            makeItem(name: "Navy jacket", category: .outerwear, color: "Navy")
        ]

        var filters = ClosetFilters()
        filters.colors = [try #require(ClosetFilterText.key("burnt sienna"))]

        #expect(names(filters.apply(to: closet)) == ["Odd jacket"])
    }

    @Test("An all-year garment is not returned by a filter for Summer, because folding it in would make Summer quietly mean something other than what the chip says")
    func seasonMatchingIsLiteral() {
        let closet = [
            makeItem(name: "Linen shirt", category: .top, seasons: [.summer]),
            makeItem(name: "Cotton tee", category: .top, seasons: [.allSeason])
        ]

        var summer = ClosetFilters()
        summer.seasons = [.summer]
        #expect(names(summer.apply(to: closet)) == ["Linen shirt"])

        // And both are reachable together, which is what OR-within-a-facet
        // is for.
        summer.seasons = [.summer, .allSeason]
        #expect(names(summer.apply(to: closet)) == ["Linen shirt", "Cotton tee"])
    }

    @Test("A garment that has never been worn matches no recency window at all, rather than sliding into 'over 6 months ago' — that band is a statement about a date, and this garment has none")
    func neverWornMatchesNoRecencyWindow() {
        let closet = [makeItem(name: "Unworn coat", category: .outerwear, wearCount: 0, lastWornAt: nil)]

        for window in ClosetWearRecency.allCases {
            var filters = ClosetFilters()
            filters.wearRecency = [window]
            #expect(filters.apply(to: closet, asOf: Self.reference).isEmpty)
        }

        // It is reachable through the axis that does describe it.
        var notWornYet = ClosetFilters()
        notWornYet.wearCounts = [.notWornYet]
        #expect(names(notWornYet.apply(to: closet, asOf: Self.reference)) == ["Unworn coat"])
    }

    @Test("A negative wear count belongs to the not-worn-yet band rather than to none of them, so bad data cannot make a garment invisible to every wear filter at once")
    func negativeWearCountIsStillInABand() {
        #expect(ClosetWearBand.notWornYet.contains(wearCount: -3))
        #expect(ClosetWearBand.allCases.filter { $0.contains(wearCount: -3) }.count == 1)

        for count in 0...25 {
            #expect(ClosetWearBand.allCases.filter { $0.contains(wearCount: count) }.count == 1)
        }
    }
}

// MARK: - isEmpty and the badge count

extension ClosetFiltersTests {

    @Test("A fresh filter set is empty and narrows nothing")
    func freshFiltersAreEmpty() {
        let filters = ClosetFilters()
        #expect(filters.isEmpty)
        #expect(filters.activeFacetCount == 0)
    }

    @Test("The badge counts facets rather than values, because three categories is one question the user asked and a badge reading 3 would tell him he has three things to undo")
    func facetCountCountsFacetsNotValues() {
        var filters = ClosetFilters()
        filters.categories = [.top, .bottom, .shoes]

        #expect(filters.isEmpty == false)
        #expect(filters.activeFacetCount == 1)

        filters.colors = ["navy"]
        #expect(filters.activeFacetCount == 2)
    }

    @Test("Both wear axes together count as the one facet spec §6.14 names, so the badge can never claim a ninth filter that is not in the spec")
    func wearAxesCountAsOneFacet() {
        var filters = ClosetFilters()
        filters.wearCounts = [.tenOrMore]
        #expect(filters.activeFacetCount == 1)

        filters.wearRecency = [.withinMonth]
        #expect(filters.activeFacetCount == 1)

        filters.wearCounts = []
        #expect(filters.activeFacetCount == 1)
    }

    @Test("Every facet on at once counts eight, matching the eight filters spec §6.14 lists")
    func allEightFacets() {
        var filters = ClosetFilters()
        filters.categories = [.top]
        filters.colors = ["navy"]
        filters.seasons = [.summer]
        filters.brands = ["apc"]
        filters.conditions = [.good]
        filters.fits = [.slim]
        filters.availability = [.available]
        filters.wearCounts = [.tenOrMore]
        filters.wearRecency = [.withinMonth]

        #expect(filters.activeFacetCount == 8)

        filters.clear()
        #expect(filters.activeFacetCount == 0)
        #expect(filters.isEmpty)
    }
}

// MARK: - What the panel is allowed to offer

@Suite("ClosetFilterOptions — spec §6.14, and spec §22's rule against dead controls")
struct ClosetFilterOptionsTests {

    private static let reference = Date(timeIntervalSince1970: 1_750_000_000)

    private func daysAgo(_ days: Int) -> Date {
        Self.reference.addingTimeInterval(TimeInterval(-days * 86_400))
    }

    private func makeItem(
        name: String = "Piece",
        category: ClothingCategory = .top,
        color: String? = nil,
        brand: String? = nil,
        seasons: [Season] = [],
        condition: ItemCondition? = nil,
        fit: ItemFit? = nil,
        availability: AvailabilityState = .available,
        wearCount: Int = 0,
        lastWornAt: Date? = nil,
        archivedAt: Date? = nil
    ) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: name,
            brand: brand,
            category: category,
            primaryColor: color,
            fit: fit,
            condition: condition,
            seasonality: seasons,
            wearCount: wearCount,
            lastWornAt: lastWornAt,
            availabilityState: availability,
            archivedAt: archivedAt
        )
    }
}

extension ClosetFilterOptionsTests {

    @Test("Only values some garment actually carries are offered, so a chip can never lead to an empty screen on its own")
    func onlyValuesPresentInTheClosetAreOffered() {
        let closet = [
            makeItem(category: .top, condition: .good),
            makeItem(category: .bottom, condition: .worn)
        ]

        let options = ClosetFilterOptions.derive(from: closet, asOf: Self.reference)

        #expect(options.categories == [.top, .bottom])
        #expect(options.conditions == [.good, .worn])
    }

    @Test("Every offered value returns at least one garment when applied on its own — the property that makes the panel's chips honest, checked exhaustively rather than facet by facet")
    func everyOfferedValueMatchesSomething() {
        let closet = [
            makeItem(name: "Shirt", category: .top, color: "Navy", brand: "A.P.C.", seasons: [.summer],
                     condition: .good, fit: .tailored, wearCount: 14, lastWornAt: daysAgo(4)),
            makeItem(name: "Jeans", category: .bottom, color: "Indigo", brand: "Levi's", seasons: [.allSeason],
                     condition: .worn, fit: .slim, availability: .inLaundry, wearCount: 2, lastWornAt: daysAgo(90)),
            makeItem(name: "Coat", category: .outerwear, color: "Olive", brand: "Uniqlo", seasons: [.fall],
                     condition: .likeNew, fit: .relaxed, wearCount: 0)
        ]

        let options = ClosetFilterOptions.derive(from: closet, asOf: Self.reference)
        var probes: [ClosetFilters] = []
        probes += singleValueFilters(options.categories, \.categories)
        probes += singleValueFilters(options.colors.map(\.key), \.colors)
        probes += singleValueFilters(options.seasons, \.seasons)
        probes += singleValueFilters(options.brands.map(\.key), \.brands)
        probes += singleValueFilters(options.conditions, \.conditions)
        probes += singleValueFilters(options.fits, \.fits)
        probes += singleValueFilters(options.availability, \.availability)
        probes += singleValueFilters(options.wearCounts, \.wearCounts)
        probes += singleValueFilters(options.wearRecency, \.wearRecency)

        // The assertion is worthless if nothing was offered in the first
        // place, so the fixture's own coverage is pinned too.
        #expect(probes.count == 25)
        for probe in probes {
            #expect(probe.apply(to: closet, asOf: Self.reference).isEmpty == false)
        }
    }

    /// One filter set per offered value, each with that value alone on.
    private func singleValueFilters<Value: Hashable>(
        _ values: [Value],
        _ facet: WritableKeyPath<ClosetFilters, Set<Value>>
    ) -> [ClosetFilters] {
        values.map { value in
            var filters = ClosetFilters()
            filters[keyPath: facet] = [value]
            return filters
        }
    }

    @Test("A facet whose only value covers the whole closet is dropped entirely, because a chip that changes nothing when tapped is the dead control spec §22 rules out")
    func aFacetThatCannotNarrowIsDropped() {
        let allTops = [
            makeItem(name: "Shirt", category: .top, condition: .good),
            makeItem(name: "Tee", category: .top, condition: .worn)
        ]

        let options = ClosetFilterOptions.derive(from: allTops, asOf: Self.reference)

        // Every garment is a top and every garment is available, so neither
        // facet can narrow anything.
        #expect(options.categories.isEmpty)
        #expect(options.availability.isEmpty)
        // Condition still separates them, so it is offered.
        #expect(options.conditions == [.good, .worn])
    }

    @Test("An empty closet offers nothing at all, which is what tells the presenter to withhold the filter control rather than open a panel onto an empty room")
    func emptyClosetOffersNothing() {
        #expect(ClosetFilterOptions.derive(from: [], asOf: Self.reference).isEmpty)
    }

    @Test("One brand recorded three ways is offered once, spelled the way most of the closet spells it — three chips each hiding two thirds of the jackets would be worse than none")
    func brandSpellingsMergeIntoOneValue() throws {
        let closet = [
            makeItem(name: "Blazer", brand: "A.P.C."),
            makeItem(name: "Cardigan", brand: "A.P.C."),
            makeItem(name: "Trousers", category: .bottom, brand: "apc"),
            makeItem(name: "Scarf", category: .accessory, brand: "Acne Studios")
        ]

        let options = ClosetFilterOptions.derive(from: closet, asOf: Self.reference)
        let apc = try #require(options.brands.first { $0.key == "apc" })

        #expect(options.brands.count == 2)
        #expect(apc.displayName == "A.P.C.")

        var filters = ClosetFilters()
        filters.brands = [apc.key]
        #expect(filters.apply(to: closet, asOf: Self.reference).count == 3)
    }

    @Test("A closet with no brands on file offers no brand heading, rather than an empty one the user opens to find nothing")
    func closetWithNoBrandsOffersNoBrandFacet() {
        let closet = [makeItem(name: "Shirt"), makeItem(name: "Tee", category: .bottom)]

        #expect(ClosetFilterOptions.derive(from: closet, asOf: Self.reference).brands.isEmpty)
    }

    @Test("A brand recorded as whitespace is not offered as a value, because a chip with nothing written on it is a control the user cannot read")
    func blankBrandIsNotOffered() {
        let closet = [
            makeItem(name: "Shirt", brand: "   "),
            makeItem(name: "Jeans", category: .bottom, brand: "Levi's")
        ]

        let options = ClosetFilterOptions.derive(from: closet, asOf: Self.reference)

        #expect(options.brands.map(\.key) == ["levis"])
    }

    @Test("A colour word this build has no swatch for is still offered, in the user's own spelling — the colour vocabulary belongs to him and the panel renders the word alone rather than a guessed rectangle")
    func unknownColourWordIsStillOffered() throws {
        let closet = [
            makeItem(name: "Odd jacket", category: .outerwear, color: "Burnt sienna"),
            makeItem(name: "Navy jacket", category: .outerwear, color: "Navy")
        ]

        let options = ClosetFilterOptions.derive(from: closet, asOf: Self.reference)
        let sienna = try #require(options.colors.first { $0.key == "burntsienna" })

        #expect(sienna.displayName == "Burnt sienna")
        // The swatch table has never heard of it, which is exactly the case
        // the panel renders as a bare word.
        #expect(AstraGarmentColor.swatch(for: sienna.displayName).hex == nil)
    }

    @Test("An archived garment takes its values with it, so a brand the user no longer owns anything in stops being offered")
    func archivedGarmentsDoNotKeepTheirValues() {
        let closet = [
            makeItem(name: "Kept shirt", brand: "Uniqlo"),
            makeItem(name: "Archived blazer", category: .outerwear, brand: "A.P.C.", archivedAt: Self.reference)
        ]

        let options = ClosetFilterOptions.derive(from: closet, asOf: Self.reference)

        // Only one garment survives the archive filter, so no facet can
        // narrow it — including the brand facet that would otherwise have
        // offered a label nobody owns any more.
        #expect(options.brands.isEmpty)
        #expect(options.isEmpty)
    }

    @Test("A closet nobody has marked anything worn in offers no wear heading, because every band there matches nothing or everything")
    func wearFacetIsDroppedWhenNothingHasBeenWorn() {
        let closet = [
            makeItem(name: "Shirt", condition: .good, wearCount: 0),
            makeItem(name: "Jeans", category: .bottom, condition: .worn, wearCount: 0)
        ]

        let options = ClosetFilterOptions.derive(from: closet, asOf: Self.reference)

        #expect(options.wearCounts.isEmpty)
        #expect(options.wearRecency.isEmpty)
        // The closet is still filterable by something, so this is the wear
        // facet being dropped rather than the whole panel being empty.
        #expect(options.conditions == [.good, .worn])
    }

    @Test("Once anything has been worn the wear heading appears, which is what keeps it a live control on real data rather than a permanently empty one")
    func wearFacetAppearsOnceThereIsWearData() {
        let closet = [
            makeItem(name: "Shirt", wearCount: 11, lastWornAt: daysAgo(3)),
            makeItem(name: "Jeans", category: .bottom, wearCount: 0)
        ]

        let options = ClosetFilterOptions.derive(from: closet, asOf: Self.reference)

        #expect(options.wearCounts == [.notWornYet, .tenOrMore])
        #expect(options.wearRecency == [.withinMonth])
    }

    @Test("Colours are offered with the closet's dominant ones first, so the order is about the wardrobe rather than about the alphabet, and is stable between recomputations")
    func coloursAreOrderedByHowMuchOfTheClosetTheyCover() {
        let closet = [
            makeItem(name: "Shirt", color: "Navy"),
            makeItem(name: "Tee", color: "Navy"),
            makeItem(name: "Coat", category: .outerwear, color: "Olive"),
            makeItem(name: "Belt", category: .accessory, color: "Tan")
        ]

        let options = ClosetFilterOptions.derive(from: closet, asOf: Self.reference)

        #expect(options.colors.map(\.displayName) == ["Navy", "Olive", "Tan"])
        #expect(ClosetFilterOptions.derive(from: closet, asOf: Self.reference) == options)
    }
}
