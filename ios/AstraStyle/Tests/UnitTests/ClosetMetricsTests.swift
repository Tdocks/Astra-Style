//
//  ClosetMetricsTests.swift
//  AstraStyleTests
//
//  Spec §6.14 "Closet overview" — the metrics block (total items,
//  estimated closet value, average cost per wear, most worn, least worn),
//  and P3-CLOSET-04's first acceptance criterion: "Metrics recompute
//  correctly after adding, archiving, or marking an item worn."
//
//  The recomputation suite at the bottom of this file is that criterion.
//  It is stated as three mutations applied to an array, because that is the
//  claim `ClosetMetrics` makes about itself: the metrics are a pure
//  function of the closet, so a mutation cannot leave them stale. There is
//  no cache to invalidate and therefore no invalidation to test — what is
//  tested is that the function actually tracks each mutation.
//
//  §6.14 lists a sixth metric, versatility, which is deliberately absent
//  from `ClosetMetrics`. The reasoning is in that file's header; there is
//  nothing to assert here beyond the fact that nothing fabricates one.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("ClosetMetrics — spec §6.14 closet metrics")
struct ClosetMetricsTests {

    // MARK: - Fixtures

    private func makeItem(
        name: String = "Merino crewneck",
        pricePaid: Decimal? = nil,
        currency: String? = nil,
        wearCount: Int = 0,
        lastWornAt: Date? = nil
    ) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: name,
            brand: "Uniqlo",
            category: .top,
            subcategory: "Sweater",
            primaryColor: "navy",
            pricePaid: pricePaid,
            currency: currency,
            wearCount: wearCount,
            lastWornAt: lastWornAt
        )
    }

    /// A fixed instant so date-based tiebreaks are deterministic rather
    /// than dependent on when the suite runs.
    private static let reference = Date(timeIntervalSince1970: 1_750_000_000)

    private func daysAgo(_ days: Int) -> Date {
        Self.reference.addingTimeInterval(TimeInterval(-days * 86_400))
    }

    // MARK: - The empty closet

    @Test("An empty closet reports zero pieces and says every other metric is missing for want of a closet, rather than reporting zeroes that look like measurements")
    func emptyCloset() {
        let metrics = ClosetMetrics.compute(for: [])

        #expect(metrics.totalItems == 0)
        #expect(metrics.estimatedValue.subtotals.isEmpty)
        #expect(metrics.estimatedValue.hasAnyPrice == false)
        // Not `isComplete`: a closet with nothing in it has not had every
        // price filled in, it has had no prices to fill in.
        #expect(metrics.estimatedValue.isComplete == false)
        #expect(metrics.averageCostPerWear == .noPricesOnFile)
        #expect(metrics.mostWorn == .closetIsEmpty)
        #expect(metrics.leastWorn == .closetIsEmpty)
    }

    // MARK: - Estimated closet value

    @Test("A closet where nothing has a price reports no value at all rather than a total of zero, which would read as a worthless wardrobe")
    func noPricesAnywhere() {
        let metrics = ClosetMetrics.compute(for: [makeItem(), makeItem(), makeItem()])

        #expect(metrics.totalItems == 3)
        #expect(metrics.estimatedValue.hasAnyPrice == false)
        #expect(metrics.estimatedValue.pricedItemCount == 0)
        #expect(metrics.estimatedValue.itemsWithoutPrice == 3)
        #expect(metrics.averageCostPerWear == .noPricesOnFile)
    }

    @Test("A partially priced closet carries how many pieces the total covers, so the figure can never be shown as the whole wardrobe's worth")
    func partialPriceCoverageIsCarriedWithTheTotal() throws {
        let items = [
            makeItem(pricePaid: 248, currency: "USD"),
            makeItem(pricePaid: 152, currency: "USD"),
            makeItem(),
            makeItem()
        ]

        let value = ClosetMetrics.compute(for: items).estimatedValue
        let subtotal = try #require(value.subtotals.first)

        #expect(subtotal.amount == 400)
        #expect(subtotal.currencyCode == "USD")
        #expect(subtotal.itemCount == 2)
        #expect(value.pricedItemCount == 2)
        #expect(value.itemCount == 4)
        #expect(value.itemsWithoutPrice == 2)
        #expect(value.isComplete == false)
    }

    @Test("A fully priced closet is marked complete, which is the only state where the total is the closet's value rather than a floor under it")
    func fullyPricedClosetIsComplete() {
        let items = [makeItem(pricePaid: 100, currency: "USD"), makeItem(pricePaid: 50, currency: "USD")]
        let value = ClosetMetrics.compute(for: items).estimatedValue

        #expect(value.isComplete)
        #expect(value.itemsWithoutPrice == 0)
    }

    @Test("A negative price is left out entirely rather than subtracted, because one bad row must not drag a closet's value downward")
    func negativePriceIsExcluded() throws {
        let items = [makeItem(pricePaid: 200, currency: "USD"), makeItem(pricePaid: -50, currency: "USD")]
        let value = ClosetMetrics.compute(for: items).estimatedValue
        let subtotal = try #require(value.subtotals.first)

        #expect(subtotal.amount == 200)
        #expect(value.pricedItemCount == 1)
        #expect(value.itemsWithoutPrice == 1)
    }

    // MARK: - Mixed currencies

    @Test("A closet holding prices in two currencies reports two subtotals rather than one sum, because adding SEK to USD produces a number that means nothing")
    func mixedCurrenciesAreNeverSummedTogether() throws {
        let items = [
            makeItem(name: "Stockholm parka", pricePaid: 4200, currency: "SEK", wearCount: 10),
            makeItem(name: "Suede loafers", pricePaid: 320, currency: "USD", wearCount: 8),
            makeItem(name: "Linen shirt", pricePaid: 800, currency: "SEK", wearCount: 2)
        ]

        let value = ClosetMetrics.compute(for: items).estimatedValue

        #expect(value.spansMultipleCurrencies)
        #expect(value.subtotals.count == 2)
        // Largest first, so the currency the closet is mostly held in leads.
        #expect(value.subtotals.map(\.currencyCode) == ["SEK", "USD"])
        let leading = try #require(value.subtotals.first)
        #expect(leading.amount == 5000)
        #expect(leading.itemCount == 2)
    }

    @Test("Currency codes are matched case- and whitespace-insensitively, so one currency spelled three ways is not reported as a mixed-currency closet")
    func currencyCodesAreNormalizedBeforeBucketing() throws {
        let items = [
            makeItem(pricePaid: 100, currency: "usd"),
            makeItem(pricePaid: 100, currency: "USD "),
            makeItem(pricePaid: 100, currency: "USD")
        ]

        let value = ClosetMetrics.compute(for: items).estimatedValue
        let subtotal = try #require(value.subtotals.first)

        #expect(value.spansMultipleCurrencies == false)
        #expect(subtotal.currencyCode == "USD")
        #expect(subtotal.amount == 300)
    }

    @Test("A price with no currency recorded is read as the same fallback the item detail screen uses, so one garment never reads as two different currencies in two places")
    func missingCurrencyFallsBackToTheSameCodeAsItemDetail() throws {
        let items = [makeItem(pricePaid: 180, currency: nil), makeItem(pricePaid: 20, currency: "  ")]
        let value = ClosetMetrics.compute(for: items).estimatedValue
        let subtotal = try #require(value.subtotals.first)

        // Once literally the item detail screen's own constant, which is
        // what made this assertion worth writing. It is now the single
        // shared one both surfaces read, so the two cannot disagree by
        // construction rather than by this test noticing.
        #expect(subtotal.currencyCode == CurrencyFormatting.fallbackCurrencyCode)
        #expect(subtotal.amount == 200)
        #expect(value.spansMultipleCurrencies == false)
    }

    @Test("There is no average cost per wear across mixed currencies, and the codes are named so the row can say why instead of showing a blank")
    func mixedCurrenciesHaveNoSingleAverageCostPerWear() {
        let items = [
            makeItem(pricePaid: 4200, currency: "SEK", wearCount: 10),
            makeItem(pricePaid: 320, currency: "USD", wearCount: 8)
        ]

        #expect(ClosetMetrics.compute(for: items).averageCostPerWear == .mixedCurrencies(["SEK", "USD"]))
    }

    // MARK: - Average cost per wear

    @Test("Average cost per wear is total spend over total wears, so a priced piece nobody has worn drags it up rather than dropping out of it")
    func averageCostPerWearIsSpendOverWears() {
        let items = [
            makeItem(name: "Unworn overcoat", pricePaid: 300, currency: "USD", wearCount: 0),
            makeItem(name: "Everyday knit", pricePaid: 30, currency: "USD", wearCount: 10, lastWornAt: daysAgo(1))
        ]

        #expect(ClosetMetrics.compute(for: items).averageCostPerWear == .amount(33, currencyCode: "USD"))
    }

    @Test("Unpriced garments are kept out of the average entirely, so their wears cannot inflate the denominator against a spend they contributed nothing to")
    func unpricedGarmentsDoNotDiluteTheAverage() {
        let priced = makeItem(pricePaid: 100, currency: "USD", wearCount: 10, lastWornAt: daysAgo(1))
        let unpricedButHeavilyWorn = makeItem(name: "Old gym tee", wearCount: 90, lastWornAt: daysAgo(2))

        let withoutIt = ClosetMetrics.compute(for: [priced]).averageCostPerWear
        let withIt = ClosetMetrics.compute(for: [priced, unpricedButHeavilyWorn]).averageCostPerWear

        #expect(withoutIt == .amount(10, currencyCode: "USD"))
        #expect(withIt == withoutIt)
    }

    @Test("With prices on file but nothing worn, the average says nothing is worn yet rather than reporting zero or an infinite cost per wear")
    func averageCostPerWearWithNoWears() {
        let items = [makeItem(pricePaid: 480, currency: "USD"), makeItem(pricePaid: 190, currency: "USD")]

        #expect(ClosetMetrics.compute(for: items).averageCostPerWear == .notYetWorn)
    }

    @Test("When both a price and a wear are missing, the missing price wins the message, because that is the one the user can act on")
    func missingPriceTakesPrecedenceOverMissingWears() {
        #expect(ClosetMetrics.compute(for: [makeItem()]).averageCostPerWear == .noPricesOnFile)
    }
}

@Suite("ClosetMetrics — most worn and least worn (spec §6.14)")
struct ClosetMetricsWearExtremeTests {

    private static let reference = Date(timeIntervalSince1970: 1_750_000_000)

    private func daysAgo(_ days: Int) -> Date {
        Self.reference.addingTimeInterval(TimeInterval(-days * 86_400))
    }

    private func makeItem(name: String, wearCount: Int = 0, lastWornAt: Date? = nil) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: name,
            category: .top,
            wearCount: wearCount,
            lastWornAt: lastWornAt
        )
    }

    @Test("A closet where nothing has been worn has neither extreme, because naming one of forty untouched pieces as the least worn would be an arbitrary pick dressed up as a finding")
    func nothingWornYetHasNeitherExtreme() {
        let items = [makeItem(name: "Navy blazer"), makeItem(name: "Grey trousers"), makeItem(name: "White sneakers")]
        let metrics = ClosetMetrics.compute(for: items)

        #expect(metrics.mostWorn == .noWearHistory)
        #expect(metrics.leastWorn == .noWearHistory)
        #expect(metrics.mostWorn.selectableItemID == nil)
        #expect(metrics.leastWorn.selectableItemID == nil)
    }

    @Test("A clear winner at each end is named outright and carries the id the row routes on")
    func clearExtremesAreNamed() {
        let mostWorn = makeItem(name: "Everyday knit", wearCount: 30, lastWornAt: daysAgo(1))
        let leastWorn = makeItem(name: "Black tie shirt", wearCount: 1, lastWornAt: daysAgo(400))
        let middle = makeItem(name: "Chore coat", wearCount: 14, lastWornAt: daysAgo(6))

        let metrics = ClosetMetrics.compute(for: [middle, mostWorn, leastWorn])

        #expect(metrics.mostWorn == .item(id: mostWorn.id, name: "Everyday knit", wearCount: 30))
        #expect(metrics.leastWorn == .item(id: leastWorn.id, name: "Black tie shirt", wearCount: 1))
        #expect(metrics.mostWorn.selectableItemID == mostWorn.id)
    }

    @Test("A tie on wear count is broken by which piece was reached for most recently, which is a real ordering rather than whichever the array happened to hold first")
    func mostWornTieIsBrokenByRecency() {
        let recent = makeItem(name: "Chore coat", wearCount: 12, lastWornAt: daysAgo(2))
        let stale = makeItem(name: "Suede jacket", wearCount: 12, lastWornAt: daysAgo(90))

        // Stale first, so passing would be impossible on array order alone.
        let metrics = ClosetMetrics.compute(for: [stale, recent, makeItem(name: "Old tee", wearCount: 3, lastWornAt: daysAgo(30))])

        #expect(metrics.mostWorn == .item(id: recent.id, name: "Chore coat", wearCount: 12))
    }

    @Test("A tie on the lowest wear count is broken the other way — left alone longest wins — so the two ends of the row use mirrored rules rather than the same one")
    func leastWornTieIsBrokenByStaleness() {
        let stale = makeItem(name: "Suede jacket", wearCount: 2, lastWornAt: daysAgo(400))
        let recent = makeItem(name: "Linen shirt", wearCount: 2, lastWornAt: daysAgo(3))

        let metrics = ClosetMetrics.compute(for: [recent, stale, makeItem(name: "Everyday knit", wearCount: 30, lastWornAt: daysAgo(1))])

        #expect(metrics.leastWorn == .item(id: stale.id, name: "Suede jacket", wearCount: 2))
    }

    @Test("A tie that no date can break is reported as a tie rather than resolved arbitrarily, and reports how many pieces share the count")
    func unbreakableTieIsReportedAsATie() {
        let sameDay = daysAgo(5)
        let items = [
            makeItem(name: "Chore coat", wearCount: 12, lastWornAt: sameDay),
            makeItem(name: "Suede jacket", wearCount: 12, lastWornAt: sameDay),
            makeItem(name: "Old tee", wearCount: 3, lastWornAt: daysAgo(30))
        ]

        let metrics = ClosetMetrics.compute(for: items)

        #expect(metrics.mostWorn == .tie(itemCount: 2, wearCount: 12))
        #expect(metrics.mostWorn.selectableItemID == nil)
    }

    @Test("Once anything has been worn, the pieces still sitting at zero are a real reading and are reported as a tie at zero rather than suppressed")
    func aTieAtZeroIsRealOnceSomethingHasBeenWorn() {
        let items = [
            makeItem(name: "Everyday knit", wearCount: 30, lastWornAt: daysAgo(1)),
            makeItem(name: "Navy blazer"),
            makeItem(name: "Black tie shirt")
        ]

        #expect(ClosetMetrics.compute(for: items).leastWorn == .tie(itemCount: 2, wearCount: 0))
    }

    @Test("A garment with wears but no recorded date cannot win the most-worn tiebreak, because an unknown recency must not beat a known one")
    func undatedGarmentDoesNotWinTheRecencyTiebreak() {
        let dated = makeItem(name: "Chore coat", wearCount: 12, lastWornAt: daysAgo(30))
        let undated = makeItem(name: "Suede jacket", wearCount: 12, lastWornAt: nil)

        let metrics = ClosetMetrics.compute(for: [undated, dated, makeItem(name: "Old tee", wearCount: 1, lastWornAt: daysAgo(2))])

        #expect(metrics.mostWorn == .item(id: dated.id, name: "Chore coat", wearCount: 12))
    }

    @Test("A single garment holds both extremes at once, which is correct rather than a degenerate case to suppress")
    func oneGarmentIsBothExtremes() {
        let only = makeItem(name: "Everyday knit", wearCount: 4, lastWornAt: daysAgo(1))
        let metrics = ClosetMetrics.compute(for: [only])

        #expect(metrics.totalItems == 1)
        #expect(metrics.mostWorn == .item(id: only.id, name: "Everyday knit", wearCount: 4))
        #expect(metrics.leastWorn == .item(id: only.id, name: "Everyday knit", wearCount: 4))
    }
}

/// P3-CLOSET-04 acceptance criterion 1, verbatim: "Metrics recompute
/// correctly after adding, archiving, or marking an item worn."
///
/// Each test applies one of those three mutations to the array a screen
/// would be holding and asserts that every metric affected by it moved, and
/// moved to the right value. They are written as before/after pairs rather
/// than as assertions about one end state, because the criterion is about
/// the transition, not about a snapshot.
@Suite("ClosetMetrics recomputation — P3-CLOSET-04 acceptance criterion 1")
struct ClosetMetricsRecomputationTests {

    private static let reference = Date(timeIntervalSince1970: 1_750_000_000)

    private func daysAgo(_ days: Int) -> Date {
        Self.reference.addingTimeInterval(TimeInterval(-days * 86_400))
    }

    private func makeItem(
        name: String,
        pricePaid: Decimal? = nil,
        wearCount: Int = 0,
        lastWornAt: Date? = nil
    ) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: name,
            category: .top,
            pricePaid: pricePaid,
            currency: "USD",
            wearCount: wearCount,
            lastWornAt: lastWornAt
        )
    }

    /// Two priced, worn garments — enough for every metric to hold a real
    /// value before a mutation is applied, so a test can tell a metric that
    /// moved from one that was never populated.
    private var startingCloset: [ClosetItem] {
        [
            makeItem(name: "Chore coat", pricePaid: 400, wearCount: 3, lastWornAt: daysAgo(2)),
            makeItem(name: "Everyday knit", pricePaid: 200, wearCount: 1, lastWornAt: daysAgo(20))
        ]
    }

    // MARK: - Adding

    @Test("Adding a garment moves the count, the value, the coverage, the average and the least-worn end — every metric the new piece bears on")
    func addingAGarmentRecomputesEveryAffectedMetric() throws {
        // Bound ONCE. `startingCloset` is a computed property and
        // `makeItem` mints a fresh `UUID()` on every call, so reading it
        // twice produces two closets holding different garments that
        // happen to share names and figures. Every value assertion below
        // passed under that mistake and only the identity one — the
        // most-worn end being untouched — could catch it, which is
        // exactly the assertion it did catch.
        let closet = startingCloset
        let before = ClosetMetrics.compute(for: closet)
        let addition = makeItem(name: "Suede loafers", pricePaid: 300, wearCount: 0)

        // Front insertion, matching `ClosetViewModel.insertSavedItem(_:)`.
        let after = ClosetMetrics.compute(for: [addition] + closet)

        #expect(before.totalItems == 2)
        #expect(after.totalItems == 3)

        let beforeValue = try #require(before.estimatedValue.subtotals.first)
        let afterValue = try #require(after.estimatedValue.subtotals.first)
        #expect(beforeValue.amount == 600)
        #expect(afterValue.amount == 900)
        #expect(after.estimatedValue.pricedItemCount == 3)
        #expect(after.estimatedValue.isComplete)

        // $600 over 4 wears, then $900 over the same 4 — the new pair adds
        // spend without adding wears, which is exactly the case the
        // aggregate is built to show rather than hide.
        #expect(before.averageCostPerWear == .amount(150, currencyCode: "USD"))
        #expect(after.averageCostPerWear == .amount(225, currencyCode: "USD"))

        #expect(after.leastWorn == .item(id: addition.id, name: "Suede loafers", wearCount: 0))
        // The most-worn end is untouched by a piece nobody has worn.
        #expect(after.mostWorn == before.mostWorn)
    }

    @Test("Adding an unpriced garment leaves the total alone but widens the gap the coverage line reports, so the value cannot quietly start describing less of the closet than it says")
    func addingAnUnpricedGarmentMovesCoverageNotTheTotal() throws {
        // Bound once, for the reason spelled out in the test above: two
        // reads of this fixture are two different closets.
        let closet = startingCloset
        let before = ClosetMetrics.compute(for: closet)
        let after = ClosetMetrics.compute(for: closet + [makeItem(name: "Hand-me-down scarf")])

        let beforeValue = try #require(before.estimatedValue.subtotals.first)
        let afterValue = try #require(after.estimatedValue.subtotals.first)

        #expect(beforeValue.amount == afterValue.amount)
        #expect(before.estimatedValue.isComplete)
        #expect(after.estimatedValue.isComplete == false)
        #expect(after.estimatedValue.itemsWithoutPrice == 1)
    }

    // MARK: - Archiving

    @Test("Archiving a garment drops it out of every metric, and produces the same answer whether the row leaves the array or stays in it carrying an archived date")
    func archivingAGarmentRecomputesEveryAffectedMetricInBothShapes() throws {
        let closet = startingCloset
        let coat = try #require(closet.first)
        let knit = try #require(closet.last)

        let removedFromArray = ClosetMetrics.compute(for: [knit])

        var archivedInPlace = coat
        archivedInPlace.archivedAt = Self.reference
        let stillInArray = ClosetMetrics.compute(for: [archivedInPlace, knit])

        #expect(removedFromArray == stillInArray)
        #expect(stillInArray.totalItems == 1)

        let value = try #require(stillInArray.estimatedValue.subtotals.first)
        #expect(value.amount == 200)
        #expect(stillInArray.estimatedValue.pricedItemCount == 1)
        // $200 over 1 wear, once the coat's $400 and 3 wears are gone.
        #expect(stillInArray.averageCostPerWear == .amount(200, currencyCode: "USD"))
        #expect(stillInArray.mostWorn == .item(id: knit.id, name: "Everyday knit", wearCount: 1))
        #expect(stillInArray.leastWorn == .item(id: knit.id, name: "Everyday knit", wearCount: 1))
    }

    @Test("Archiving the last garment returns the metrics to the empty-closet states rather than leaving the last figures standing")
    func archivingTheLastGarmentReturnsToTheEmptyStates() {
        let metrics = ClosetMetrics.compute(for: [])

        #expect(metrics.totalItems == 0)
        #expect(metrics.estimatedValue.hasAnyPrice == false)
        #expect(metrics.mostWorn == .closetIsEmpty)
        #expect(metrics.leastWorn == .closetIsEmpty)
    }

    // MARK: - Marking worn

    @Test("Marking a garment worn moves the average cost per wear and nothing else about the money — spend is unchanged, the wears it is divided by are not")
    func markingWornRecomputesTheAverageCostPerWear() throws {
        let closet = startingCloset
        let coat = try #require(closet.first)
        let knit = try #require(closet.last)

        let before = ClosetMetrics.compute(for: closet)

        // Exactly what `ClosetRepository.markWorn(id:wornAt:)` writes back:
        // the count up by one, the date set to the moment it was worn.
        var wornCoat = coat
        wornCoat.wearCount += 1
        wornCoat.lastWornAt = Self.reference
        let after = ClosetMetrics.compute(for: [wornCoat, knit])

        // $600 over 4 wears, then the same $600 over 5.
        #expect(before.averageCostPerWear == .amount(150, currencyCode: "USD"))
        #expect(after.averageCostPerWear == .amount(120, currencyCode: "USD"))
        #expect(after.estimatedValue == before.estimatedValue)
        #expect(after.totalItems == before.totalItems)
    }

    @Test("Enough wears flip which piece holds each end of the row, so the two extremes track the wear counts rather than the order the array was built in")
    func markingWornFlipsWhichPieceLeads() throws {
        let closet = startingCloset
        let coat = try #require(closet.first)
        let knit = try #require(closet.last)

        let before = ClosetMetrics.compute(for: closet)
        #expect(before.mostWorn == .item(id: coat.id, name: "Chore coat", wearCount: 3))
        #expect(before.leastWorn == .item(id: knit.id, name: "Everyday knit", wearCount: 1))

        var wornKnit = knit
        wornKnit.wearCount += 5
        wornKnit.lastWornAt = Self.reference
        let after = ClosetMetrics.compute(for: [coat, wornKnit])

        #expect(after.mostWorn == .item(id: knit.id, name: "Everyday knit", wearCount: 6))
        #expect(after.leastWorn == .item(id: coat.id, name: "Chore coat", wearCount: 3))
    }

    @Test("The first wear in a closet that has never been worn replaces the no-history state with a real reading at both ends")
    func theFirstWearEndsTheNoHistoryState() throws {
        let untouched = [makeItem(name: "Navy blazer", pricePaid: 400), makeItem(name: "Grey trousers", pricePaid: 200)]
        let before = ClosetMetrics.compute(for: untouched)

        #expect(before.mostWorn == .noWearHistory)
        #expect(before.leastWorn == .noWearHistory)
        #expect(before.averageCostPerWear == .notYetWorn)

        var blazer = try #require(untouched.first)
        blazer.wearCount = 1
        blazer.lastWornAt = Self.reference
        let trousers = try #require(untouched.last)
        let after = ClosetMetrics.compute(for: [blazer, trousers])

        #expect(after.mostWorn == .item(id: blazer.id, name: "Navy blazer", wearCount: 1))
        #expect(after.leastWorn == .item(id: trousers.id, name: "Grey trousers", wearCount: 0))
        #expect(after.averageCostPerWear == .amount(600, currencyCode: "USD"))
    }
}
