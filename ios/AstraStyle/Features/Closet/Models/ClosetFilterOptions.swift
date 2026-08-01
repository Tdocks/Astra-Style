//
//  ClosetFilterOptions.swift
//  AstraStyle
//
//  Which of spec §6.14's filter values this closet can actually offer.
//
//  WHY THE OPTIONS ARE DERIVED AT ALL, RATHER THAN LISTED.
//  Two of the eight facets have no type to enumerate. `closet_items.brand`
//  and `.primary_color` are text columns and both vocabularies are
//  deliberately open (see `Components/ClosetColorPicker.swift`), so the
//  only place the available brands and colours exist is the closet itself.
//  Once two facets have to be derived from the items, deriving all eight
//  from the same pass is both cheaper and more honest than half a panel
//  built from `allCases` and half built from data.
//
//  A VALUE THAT CANNOT NARROW IS NOT OFFERED. THIS IS THE WHOLE RULE.
//  Spec §22 rules out dead controls, and a filter chip that returns
//  nothing is exactly one: the user taps it, the screen empties, and he
//  learns the panel is not to be trusted. So a value no garment carries is
//  never drawn. The rule then extends one step further, which is the part
//  worth arguing: a facet whose every remaining value covers the WHOLE
//  scope is dropped entirely. A closet of nothing but tops offers no
//  category facet, because "Tops" there is a chip that changes nothing —
//  visibly present, apparently doing something, and inert. Both halves of
//  that rule are the same idea: offer a control only where tapping it
//  changes what is on screen.
//
//  HIDE, RATHER THAN DISABLE OR COUNT.
//  Three ways to keep a user off an empty result. Disabling leaves eight
//  facets' worth of greyed chips he still has to read past, and a disabled
//  control is a promise the app will not keep. Per-chip counts ("Tops 12")
//  are the version real search engines use, and they were the tempting
//  option — but done properly the count on each chip has to be recomputed
//  against the OTHER facets every time anything is toggled, which means
//  chips shift and vanish under the user's finger mid-tap, and at eight
//  facets it doubles the amount of text in an already dense panel. Hiding
//  is quieter, is stable while the panel is open, and leaves the live
//  count where one number can carry it: the panel's primary action, which
//  says how many pieces the current set will show.
//
//  This does NOT stop a combination from matching nothing — blue tops in a
//  closet with no blue tops is still reachable, because the facets are
//  independent. That case is handled where it belongs, in the panel, which
//  says so before the user commits rather than after.
//
//  WHICH ITEMS TO DERIVE FROM, WHICH IS A CALL-SITE DECISION.
//  The panel opens over a screen that may already be narrowed by a search
//  query, so "present in the closet" and "present in what he is looking
//  at" can differ. Pass the SEARCH-NARROWED, FILTER-FREE array: every
//  offered value then corresponds to at least one garment in the scope the
//  screen is actually showing, and the option list stays still while the
//  panel is open because the query cannot change behind it. Deriving from
//  the whole closet instead would offer brands the search has already
//  excluded; deriving from the FILTERED array would delete the chip the
//  user just tapped out from under him.
//

import Foundation

/// One derived free-text filter value: the key that matches, and the
/// spelling to put on the chip.
///
/// Two fields rather than one because the two jobs disagree. Matching has
/// to be insensitive to case, accents and punctuation or a closet holding
/// both "A.P.C." and "apc" offers two chips that each hide half the
/// jackets. Display has to be the user's own spelling, because showing a
/// man `apc` for a brand he wrote as "A.P.C." is the app correcting him.
public struct ClosetFilterValue: Equatable, Hashable, Sendable, Identifiable {

    /// The folded key stored in `ClosetFilters.colors` / `.brands`.
    public let key: String

    /// The spelling shown to the user.
    public let displayName: String

    public var id: String { key }

    fileprivate init(key: String, displayName: String) {
        self.key = key
        self.displayName = displayName
    }
}

/// The §6.14 filter values a given closet can offer, derived from its
/// items and nothing else.
///
/// A pure value like `ClosetMetrics`, and for the same reason: there is no
/// cache to invalidate, so a closet that gains a garment cannot leave a
/// stale option list behind.
public struct ClosetFilterOptions: Equatable, Sendable {

    /// Ordered by `allCases` — the spec's own category order — rather than
    /// alphabetically. That holds for every enum-backed facet below: their
    /// declaration order is meaningful (condition runs new to well worn,
    /// fit runs slim to oversized) and sorting them by label would shuffle
    /// a scale into nonsense.
    public let categories: [ClothingCategory]

    /// Ordered by how many garments carry each colour, most first, so the
    /// closet's dominant colours lead. Ties break on the label, so the
    /// order is stable between recomputations rather than dependent on
    /// dictionary hashing.
    public let colors: [ClosetFilterValue]

    public let seasons: [Season]

    /// Ordered by garment count like `colors`.
    public let brands: [ClosetFilterValue]

    public let conditions: [ItemCondition]

    public let fits: [ItemFit]

    public let availability: [AvailabilityState]

    public let wearCounts: [ClosetWearBand]

    public let wearRecency: [ClosetWearRecency]

    /// Whether there is nothing to filter by at all.
    ///
    /// True for an empty closet, and also for a small uniform one — five
    /// navy t-shirts of the same brand, condition and fit differ in
    /// nothing, so no facet can narrow them. A caller that draws a filter
    /// control regardless would be drawing a door onto an empty room; the
    /// panel says so plainly, and `ClosetFilterButton`'s own
    /// documentation says where the control should be withheld instead.
    public var isEmpty: Bool {
        categories.isEmpty
            && colors.isEmpty
            && seasons.isEmpty
            && brands.isEmpty
            && conditions.isEmpty
            && fits.isEmpty
            && availability.isEmpty
            && wearCounts.isEmpty
            && wearRecency.isEmpty
    }

    /// Private so `derive(from:)` is the only way to obtain one.
    ///
    /// The same guard `ClosetMetrics` uses: a public memberwise
    /// initialiser would let a caller assemble an option list that
    /// describes no closet — a brand chip for a brand nobody owns — which
    /// is precisely the dead control this type exists to prevent.
    private init(
        categories: [ClothingCategory],
        colors: [ClosetFilterValue],
        seasons: [Season],
        brands: [ClosetFilterValue],
        conditions: [ItemCondition],
        fits: [ItemFit],
        availability: [AvailabilityState],
        wearCounts: [ClosetWearBand],
        wearRecency: [ClosetWearRecency]
    ) {
        self.categories = categories
        self.colors = colors
        self.seasons = seasons
        self.brands = brands
        self.conditions = conditions
        self.fits = fits
        self.availability = availability
        self.wearCounts = wearCounts
        self.wearRecency = wearRecency
    }

    /// Derives every offerable filter value from a closet, as of now.
    public static func derive(from items: [ClosetItem]) -> ClosetFilterOptions {
        derive(from: items, asOf: .now)
    }

    /// Derives every offerable filter value from a closet, as of a given
    /// instant.
    ///
    /// The instant is only used by the wear-recency windows, and exists
    /// for the same reason `ClosetFilters.apply(to:asOf:)` takes one: so
    /// the bands a test asserts on are the bands it constructed, not
    /// whichever ones the clock produced while the suite ran.
    ///
    /// Archived garments are dropped first, mirroring
    /// `ClosetMetrics.compute(for:)`: archiving is a soft delete, so a
    /// brand the user owns nothing in any more must not keep its chip.
    public static func derive(from items: [ClosetItem], asOf now: Date) -> ClosetFilterOptions {
        let active = items.filter { !$0.isArchived }

        return ClosetFilterOptions(
            categories: offered(ClothingCategory.allCases, in: active) { $0 == $1.category },
            colors: offeredText(in: active) { item in
                var words = item.secondaryColors
                if let primary = item.primaryColor { words.insert(primary, at: 0) }
                return words
            },
            seasons: offered(Season.allCases, in: active) { $1.seasonality.contains($0) },
            brands: offeredText(in: active) { item in item.brand.map { [$0] } ?? [] },
            conditions: offered(ItemCondition.allCases, in: active) { $0 == $1.condition },
            fits: offered(ItemFit.allCases, in: active) { $0 == $1.fit },
            availability: offered(AvailabilityState.allCases, in: active) { $0 == $1.availabilityState },
            wearCounts: offered(ClosetWearBand.allCases, in: active) { $0.contains(wearCount: $1.wearCount) },
            wearRecency: offered(ClosetWearRecency.allCases, in: active) {
                $0.contains(lastWornAt: $1.lastWornAt, asOf: now)
            }
        )
    }
}

// MARK: - The offering rule

extension ClosetFilterOptions {

    /// Keeps the values at least one garment carries, and drops the whole
    /// facet when every one of them covers the entire scope.
    ///
    /// The second half is what makes this more than a presence check. A
    /// closet of nothing but available garments has one availability value
    /// present, and it matches all of them — selecting it is a tap that
    /// changes nothing, which §22 calls a dead control. An empty closet
    /// falls out of the same test without a special case: nothing is
    /// present, so nothing narrows, so the facet is empty.
    ///
    /// Deliberately not `Sequence.count(where:)`: this runs per value per
    /// facet on an array the user is looking at, and a manual count avoids
    /// building an intermediate array for each of roughly sixty values.
    fileprivate static func offered<Value>(
        _ values: [Value],
        in items: [ClosetItem],
        matching: (Value, ClosetItem) -> Bool
    ) -> [Value] {
        let total = items.count
        var present: [Value] = []
        var anyValueNarrows = false

        for value in values {
            var count = 0
            for item in items where matching(value, item) {
                count += 1
            }
            guard count > 0 else { continue }
            present.append(value)
            if count < total { anyValueNarrows = true }
        }

        return anyValueNarrows ? present : []
    }

    /// The same rule for the two free-text facets, which have to build
    /// their own value set before they can count it.
    ///
    /// `words` returns every string on one garment that belongs to this
    /// facet — one brand, or a primary colour plus its secondaries.
    ///
    /// A GARMENT COUNTS ONCE PER KEY, however many of its words fold to
    /// it. A shirt recorded as navy with a navy stripe is one navy
    /// garment, and counting it twice would push navy up the order on the
    /// strength of a duplicate.
    ///
    /// THE SPELLING SHOWN IS THE ONE MOST GARMENTS USE. Ties break on the
    /// spelling that sorts first — arbitrary, but stable, which is the
    /// property that matters: a chip that renamed itself between
    /// recomputations would look like a bug in the closet rather than a
    /// tiebreak in a sort.
    fileprivate static func offeredText(
        in items: [ClosetItem],
        words: (ClosetItem) -> [String]
    ) -> [ClosetFilterValue] {
        var garmentsPerKey: [String: Int] = [:]
        var spellingsPerKey: [String: [String: Int]] = [:]

        for item in items {
            var countedKeys: Set<String> = []
            for word in words(item) {
                guard let key = ClosetFilterText.key(word) else { continue }
                spellingsPerKey[key, default: [:]][ClosetFilterText.displayForm(word), default: 0] += 1
                if countedKeys.insert(key).inserted {
                    garmentsPerKey[key, default: 0] += 1
                }
            }
        }

        let total = items.count
        guard garmentsPerKey.contains(where: { $0.value < total }) else { return [] }

        return garmentsPerKey
            .compactMap { key, count -> (value: ClosetFilterValue, count: Int)? in
                guard let spellings = spellingsPerKey[key],
                      let display = bestSpelling(among: spellings) else { return nil }
                return (ClosetFilterValue(key: key, displayName: display), count)
            }
            .sorted { lhs, rhs in
                lhs.count == rhs.count
                    ? lhs.value.displayName < rhs.value.displayName
                    : lhs.count > rhs.count
            }
            .map(\.value)
    }

    /// The most-used spelling of one folded key, ties broken by sort order.
    private static func bestSpelling(among spellings: [String: Int]) -> String? {
        spellings
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .first?
            .key
    }
}
