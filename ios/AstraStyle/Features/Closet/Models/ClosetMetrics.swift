//
//  ClosetMetrics.swift
//  AstraStyle
//
//  The metrics block of spec §6.14 "Closet overview": total items,
//  estimated closet value, average cost per wear, most worn, least worn.
//
//  A PURE FUNCTION OF THE ARRAY, AND THAT IS THE WHOLE DESIGN.
//  The ticket's acceptance criterion is "metrics recompute correctly after
//  adding, archiving, or marking an item worn". There are two ways to
//  satisfy that: recompute on every mutation, or make the metrics a value
//  derived from the array so that there is no such thing as a stale one.
//  The first is satisfied by remembering; the second is satisfied by
//  construction. This file is the second — `compute(for:)` is the only way
//  to make a `ClosetMetrics`, the memberwise initialiser is private, and
//  nothing here is stored on the view model. A future writer who adds a
//  fourth mutation to `ClosetViewModel` cannot forget to invalidate a cache
//  that does not exist.
//
//  That also decides where it is called from: `ClosetViewModel.allItems`
//  and `visibleItems` are already derived rather than stored (see that
//  file's header), so a metrics property beside them is one more derivation
//  of the same source, not a second source of truth.
//
//  ARCHIVED GARMENTS ARE EXCLUDED HERE, NOT ONLY BY THE CALLER.
//  Archiving is a soft delete (`ClosetItem.archivedAt`, spec §9) and
//  `LiveClosetRepository.fetchItems()` already filters archived rows out,
//  so in practice the screen's array never holds one. The filter is
//  repeated in `compute(for:)` anyway, because the criterion says
//  "recompute correctly after archiving" and there are two shapes that
//  mutation can arrive in — the row leaves the array, or the row stays and
//  gains an `archivedAt`. Both must produce the same numbers, and a jacket
//  the user has archived must not keep inflating what his closet is worth.
//
//  UNKNOWN IS A CASE, NOT A ZERO.
//  Every metric that can fail to have an answer says WHY it has no answer,
//  in a distinct case, rather than collapsing to `nil`, `0` or an em dash.
//  This is the pattern `CostPerWearDisplay` established on the item detail
//  screen for exactly the same reason: one `nil` covering three different
//  causes forces the view to invent a sentence, and the three causes are
//  not the same sentence to the man reading them. `0` in particular is a
//  measurement, not a gap — spec §22 rules out dead numbers and placeholder
//  values, and "$0.00" for a closet nobody has priced is both.
//
//  WHY THERE IS NO `versatility` MEMBER, THOUGH §6.14 LISTS ONE.
//  Versatility is defined — precisely, in docs/05-wardrobe-graph.md §5.1 —
//  as the count of distinct outfits an item appears in with a compatibility
//  score of at least 0.65, normalised against a size-indexed expectation
//  curve. Every input to that definition is Phase 4 work: there is no
//  outfit data on the device, and the compatibility scorer it depends on
//  has not been built. `WardrobeScore.versatility` is a field on a struct
//  whose only producer, `LiveClosetRepository.fetchWardrobeScore()`, throws
//  `AstraError.unimplemented` unconditionally — there is no
//  `wardrobe_scores` table behind it.
//
//  Three options existed. Fetch it and hide the metric when it throws: this
//  type is a pure function of an item array and cannot fetch anything, and
//  `ClosetViewModel`'s header already records why that call is not made on
//  this screen at all. Compute a client-side substitute from data that does
//  exist — category spread, colour spread, formality range: this is the one
//  that had to be turned down deliberately. Any of those is a defensible
//  number about *something*, but none of them is versatility, and it would
//  render in the same type, in the same row, beside four measured figures,
//  indistinguishable from them. Worse, it would move — sometimes sharply —
//  the day the real scorer lands, for reasons the user could never connect
//  to anything he did. That is the confounded reading this codebase's rule
//  names: absent is honest; a confounded reading is not.
//
//  So the metric is absent, and this comment is the record of the gap. When
//  Phase 4 lands, versatility arrives as a real member here, fed by real
//  outfit data, and the row grows a sixth tile. Nothing about the shape of
//  this file has to change for that.
//

import Foundation

/// The §6.14 metrics, derived from a closet's items and nothing else.
///
/// `Sendable` and nonisolated on purpose: this is a value computed from
/// values, with no view or view-model state anywhere in it, so it can be
/// built on whichever actor happens to be holding the array.
public struct ClosetMetrics: Equatable, Sendable {

    /// How many garments the closet holds, archived pieces excluded.
    public let totalItems: Int

    /// What the closet is worth, split by currency, carrying how much of
    /// the closet the figure actually covers.
    public let estimatedValue: EstimatedValue

    /// Total spend over total wears across the priced garments, or the
    /// reason there is no such number.
    public let averageCostPerWear: AverageCostPerWear

    /// The single most-worn garment, the tie it is part of, or the reason
    /// there is no most-worn garment.
    public let mostWorn: WearExtreme

    /// The single least-worn garment, the tie it is part of, or the reason
    /// there is no least-worn garment.
    public let leastWorn: WearExtreme

    /// Private so that `compute(for:)` is the only way to obtain a
    /// `ClosetMetrics`.
    ///
    /// A public memberwise initialiser would let a caller assemble a set of
    /// metrics that never described any closet — 5 items alongside a value
    /// covering 40 of them — which is precisely the drift this type exists
    /// to make impossible. Previews and tests build one the way the app
    /// does: from an array of garments.
    private init(
        totalItems: Int,
        estimatedValue: EstimatedValue,
        averageCostPerWear: AverageCostPerWear,
        mostWorn: WearExtreme,
        leastWorn: WearExtreme
    ) {
        self.totalItems = totalItems
        self.estimatedValue = estimatedValue
        self.averageCostPerWear = averageCostPerWear
        self.mostWorn = mostWorn
        self.leastWorn = leastWorn
    }

    /// Derives every §6.14 metric from the closet as it currently stands.
    ///
    /// Cheap enough to call from a computed view-model property: one filter
    /// and a handful of single passes over an array whose size is one man's
    /// wardrobe, not a catalogue.
    public static func compute(for items: [ClosetItem]) -> ClosetMetrics {
        let active = items.filter { !$0.isArchived }
        let priced = active.compactMap(PricedItem.init(item:))

        return ClosetMetrics(
            totalItems: active.count,
            estimatedValue: EstimatedValue(priced: priced, itemCount: active.count),
            averageCostPerWear: AverageCostPerWear(priced: priced),
            mostWorn: WearExtreme.mostWorn(in: active),
            leastWorn: WearExtreme.leastWorn(in: active)
        )
    }
}

// MARK: - Estimated closet value

extension ClosetMetrics {

    /// One currency's share of the closet's value.
    public struct CurrencySubtotal: Equatable, Sendable, Identifiable {
        /// Normalised currency code — see
        /// `CurrencyFormatting.normalizedCurrencyCode(_:)`.
        public let currencyCode: String

        /// The sum of the prices recorded in this currency.
        public let amount: Decimal

        /// How many garments contributed to `amount`.
        public let itemCount: Int

        public var id: String { currencyCode }

        /// Formatted in its own currency, never converted into another.
        public var formattedAmount: String {
            CurrencyFormatting.formatted(amount, code: currencyCode)
        }

        fileprivate init(currencyCode: String, amount: Decimal, itemCount: Int) {
            self.currencyCode = currencyCode
            self.amount = amount
            self.itemCount = itemCount
        }
    }

    /// Spec §6.14's "Estimated closet value", and the two things that make
    /// the word *estimated* honest rather than decorative.
    ///
    /// FIRST, COVERAGE TRAVELS WITH THE TOTAL.
    /// `pricePaid` is optional and most garments will not have one. A
    /// closet of 40 pieces where 3 carry a price sums to $400 and reads as
    /// a $400 wardrobe — a figure that is arithmetically correct and
    /// completely false as a statement about the closet. So the number of
    /// priced garments and the size of the closet are part of this value
    /// rather than something a view has to remember to mention. Any surface
    /// that renders `subtotals` without also rendering the coverage is
    /// misreporting, and keeping the numbers in one value is what makes
    /// that visible in review rather than invisible.
    ///
    /// SECOND, CURRENCIES ARE NEVER ADDED TOGETHER.
    /// `currency` is per item, so a closet legitimately holds a jacket in
    /// SEK and boots in USD. There is no exchange rate on the device, none
    /// in spec §14, and a stale one would be worse than none — so the total
    /// is a list of per-currency subtotals rather than a scalar. A closet
    /// in a single currency, which is nearly all of them, produces a
    /// one-element list and reads as one figure.
    public struct EstimatedValue: Equatable, Sendable {

        /// One entry per currency present, largest first, ties broken by
        /// code so the order is stable across recomputations.
        public let subtotals: [CurrencySubtotal]

        /// How many garments had a usable price.
        public let pricedItemCount: Int

        /// How many garments are in the closet at all.
        public let itemCount: Int

        /// How many garments contributed nothing to the total.
        public var itemsWithoutPrice: Int { max(itemCount - pricedItemCount, 0) }

        /// Whether there is any figure to show at all.
        public var hasAnyPrice: Bool { !subtotals.isEmpty }

        /// Whether the total covers the whole closet rather than part of
        /// it. Only then is the figure a closet value rather than a floor.
        public var isComplete: Bool { itemCount > 0 && itemsWithoutPrice == 0 }

        /// Whether the closet holds prices in more than one currency.
        public var spansMultipleCurrencies: Bool { subtotals.count > 1 }

        fileprivate init(priced: [PricedItem], itemCount: Int) {
            var totals: [String: (amount: Decimal, count: Int)] = [:]
            for item in priced {
                let running = totals[item.currencyCode] ?? (amount: .zero, count: 0)
                totals[item.currencyCode] = (running.amount + item.amount, running.count + 1)
            }

            self.subtotals = totals
                .map { CurrencySubtotal(currencyCode: $0.key, amount: $0.value.amount, itemCount: $0.value.count) }
                .sorted { lhs, rhs in
                    // Largest first, so the currency the closet is mostly
                    // in leads. Code as the tiebreak rather than dictionary
                    // order, which is not stable — an unstable order would
                    // reshuffle the row on every recomputation and would
                    // make `Equatable` depend on hash seeding.
                    lhs.amount == rhs.amount ? lhs.currencyCode < rhs.currencyCode : lhs.amount > rhs.amount
                }
            self.pricedItemCount = priced.count
            self.itemCount = itemCount
        }
    }
}

// MARK: - Average cost per wear

extension ClosetMetrics {

    /// Spec §6.14's "Average cost per wear", or the reason there is none.
    ///
    /// The arithmetic is `CostPerWearCalculator.averageCostPerWear(items:)`
    /// and is deliberately not reimplemented here: it is total spend over
    /// total wears rather than the mean of each garment's own figure, so a
    /// never-worn expensive coat drags the average UP instead of vanishing
    /// out of it. That property is the point of the metric and is already
    /// pinned by that calculator's own tests.
    ///
    /// WHICH GARMENTS ARE FED TO IT, AND WHY IT IS NOT ALL OF THEM.
    /// Only garments with a usable price go in. Passing the whole closet
    /// would put unpriced garments' wears into the denominator while they
    /// contribute nothing to the numerator, so every worn-but-unpriced
    /// piece would quietly pull the average down — a numerator over one set
    /// of garments divided by a denominator over a larger set. Both halves
    /// of the ratio therefore describe the same garments, and the view says
    /// out loud which garments those are.
    public enum AverageCostPerWear: Equatable, Sendable {

        /// A real figure, in the currency every priced garment shares.
        case amount(Decimal, currencyCode: String)

        /// Nothing in the closet has a purchase price on file.
        ///
        /// Checked BEFORE `notYetWorn`, mirroring the precedence
        /// `ClosetItemDetailCopy.costPerWear(for:)` already sets: when both
        /// are true, the price is the one the user can do something about,
        /// and leading with "nothing worn yet" would be true, useless, and
        /// would hide the field he could actually fill in.
        case noPricesOnFile

        /// Prices are on file and none of those garments has been worn.
        /// Not "free" and not "infinite" — the number does not exist yet.
        case notYetWorn

        /// The priced garments span more than one currency, so there is no
        /// single average to state. Carries the codes, sorted, so the view
        /// can name them rather than leave a blank.
        case mixedCurrencies([String])

        fileprivate init(priced: [PricedItem]) {
            let codes = Set(priced.map(\.currencyCode)).sorted()
            guard let code = codes.first else {
                self = .noPricesOnFile
                return
            }
            guard codes.count == 1 else {
                self = .mixedCurrencies(codes)
                return
            }
            let inputs: [(pricePaid: Decimal?, wearCount: Int)] = priced.map {
                (pricePaid: $0.amount, wearCount: $0.wearCount)
            }
            guard let average = CostPerWearCalculator.averageCostPerWear(items: inputs) else {
                // Every garment here is known to carry a usable price, so
                // the calculator has exactly one remaining reason to return
                // nothing: no wears at all.
                self = .notYetWorn
                return
            }
            self = .amount(average, currencyCode: code)
        }
    }
}

// MARK: - Most worn and least worn

extension ClosetMetrics {

    /// Spec §6.14's "Most worn" / "Least worn".
    ///
    /// TIES ARE REPORTED AS TIES.
    /// Three jackets on twelve wears each have no most-worn garment between
    /// them, and naming whichever one the array happens to hold first is an
    /// arbitrary choice rendered as a finding. `lastWornAt` breaks the tie
    /// where it can, because "worn the same number of times but reached for
    /// most recently" is a real ordering rather than an array-order
    /// accident — and where it cannot (no dates recorded, or the same date
    /// on both), the tie is what gets stated.
    ///
    /// A CLOSET WITH NO WEAR HISTORY HAS NEITHER EXTREME.
    /// When every garment sits at zero, `.noWearHistory` covers both ends.
    /// Most-worn is the obvious half. Least-worn is the interesting one:
    /// reporting "40 pieces tied at 0 wears" would be arithmetically true
    /// and would dress the total absence of data up as a measurement, so
    /// the absence is stated as an absence instead. Once anything has been
    /// worn, a tie at zero IS a real reading — "the 14 pieces you have not
    /// worn yet" — and is reported as one.
    public enum WearExtreme: Equatable, Sendable {

        /// One garment holds the extreme outright.
        case item(id: UUID, name: String, wearCount: Int)

        /// Several garments share it and no tiebreak separates them.
        case tie(itemCount: Int, wearCount: Int)

        /// The closet has garments, none of which has ever been worn.
        case noWearHistory

        /// The closet has no garments.
        case closetIsEmpty

        /// The garment this metric routes to when tapped, if it is a single
        /// garment. `nil` in every other case — which is what keeps a tie
        /// or an empty state from being drawn as a control that leads
        /// nowhere (spec §22: no dead buttons).
        public var selectableItemID: UUID? {
            guard case .item(let id, _, _) = self else { return nil }
            return id
        }

        fileprivate static func mostWorn(in items: [ClosetItem]) -> WearExtreme {
            guard let peak = items.map(\.wearCount).max() else { return .closetIsEmpty }
            guard peak > 0 else { return .noWearHistory }

            let candidates = items.filter { $0.wearCount == peak }
            // Most recently reached for wins. A garment carrying wears but
            // no recorded date cannot win this — its recency is unknown,
            // and an unknown date must not beat a known one.
            let mostRecent = candidates.compactMap(\.lastWornAt).max()
            let winners = candidates.filter { $0.lastWornAt == mostRecent }
            return resolve(candidates: candidates, winners: winners, wearCount: peak)
        }

        fileprivate static func leastWorn(in items: [ClosetItem]) -> WearExtreme {
            guard let fewest = items.map(\.wearCount).min() else { return .closetIsEmpty }
            guard items.contains(where: { $0.wearCount > 0 }) else { return .noWearHistory }

            let candidates = items.filter { $0.wearCount == fewest }
            // Left alone longest wins, the mirror of most-worn's rule. Here
            // a garment with no recorded date is the extreme case of "not
            // worn recently" rather than an unknown, so those take
            // precedence over any dated garment instead of losing to one.
            let neverDated = candidates.filter { $0.lastWornAt == nil }
            let winners: [ClosetItem]
            if neverDated.isEmpty {
                let earliest = candidates.compactMap(\.lastWornAt).min()
                winners = candidates.filter { $0.lastWornAt == earliest }
            } else {
                winners = neverDated
            }
            return resolve(candidates: candidates, winners: winners, wearCount: fewest)
        }

        /// `itemCount` on a tie is how many garments share the WEAR COUNT,
        /// not how many survived the date tiebreak. The wear count is what
        /// the metric measures and what the user is being told about; the
        /// date only decides whether one of them can be singled out.
        private static func resolve(candidates: [ClosetItem], winners: [ClosetItem], wearCount: Int) -> WearExtreme {
            guard winners.count == 1, let winner = winners.first else {
                return .tie(itemCount: candidates.count, wearCount: wearCount)
            }
            return .item(id: winner.id, name: winner.name, wearCount: wearCount)
        }
    }
}

// MARK: - Priced garment

/// A garment reduced to the three facts the money metrics need, with the
/// "is this price usable" question answered once at the boundary rather
/// than at each of the two call sites.
///
/// A negative price fails to construct one, mirroring
/// `CostPerWearCalculator`, which rejects a negative price rather than
/// returning a negative cost per wear. A closet total that one bad row
/// could drag DOWNWARD would be worse than one that omits the row.
private struct PricedItem {
    let amount: Decimal
    let currencyCode: String
    let wearCount: Int

    init?(item: ClosetItem) {
        guard let amount = item.pricePaid, amount >= 0 else { return nil }
        self.amount = amount
        self.currencyCode = CurrencyFormatting.normalizedCurrencyCode(item.currency)
        self.wearCount = item.wearCount
    }
}
