//
//  ClosetFilters.swift
//  AstraStyle
//
//  Spec §6.14's filter list, verbatim: "Category. Color. Season. Brand.
//  Condition. Fit. Availability. Wear frequency." This file is the whole
//  of that behaviour — `ClosetFilterPanelView` only sets the values, and
//  `apply(to:)` is what the acceptance criteria actually verify.
//
//  OR WITHIN A FACET, AND ACROSS FACETS.
//  The criterion says the eight filters are "composable together (AND
//  semantics)", and that is about composing FACETS: a man asking for blue
//  tops wants the intersection of the two, not the union. Applied INSIDE
//  one facet, AND is useless — "category is Tops and category is Bottoms"
//  describes a garment that cannot exist, so an AND-within-facet rule
//  would make every multi-select in this panel a control whose second tap
//  always empties the screen. So values within one facet are ORed and
//  facets are ANDed, which is what every filter UI a man has already used
//  does and the only reading under which all eight facets can be
//  multi-select.
//
//  That is not left to be inferred. The panel joins a facet's chosen
//  values with the word "or" everywhere it summarises them ("Category —
//  Tops or Bottoms") and lists the facets as separate rows, so both
//  operators are visible in the copy rather than buried in a help sheet
//  nobody opens.
//
//  A GARMENT WITH NOTHING RECORDED IN A FILTERED FIELD IS EXCLUDED.
//  `brand`, `condition`, `fit` and `primaryColor` are optional, and
//  `seasonality` can be empty. Filtering a facet asks "which garments ARE
//  this", and a garment with no brand on file is not any brand, so it
//  drops out rather than passing through. The alternative — letting
//  unknowns through — means a filter for one label returns every
//  unbranded garment in the closet, which reads as the filter being
//  broken. The cost is real and accepted: a half-filled closet narrows
//  harder than the user may expect, and the way to see those garments
//  again is to turn the facet off. Deliberate, and pinned by tests.
//
//  WEAR FREQUENCY IS NOT A COLUMN, SO IT IS BUILT FROM THE TWO THAT ARE —
//  AND NOTHING HERE IS CALLED A FREQUENCY.
//  `ClosetItem` carries `wearCount: Int` and `lastWornAt: Date?`. A
//  frequency is wears per unit of time and there is no denominator on the
//  device: `purchaseDate` is optional, and `createdAt` records when the
//  garment entered the app rather than when it entered the wardrobe.
//  Dividing by either would put a number on screen whose meaning changes
//  per garment, which is worse than not offering one.
//
//  A raw count alone is not enough either, and the reason is the whole
//  problem with the word: a jacket worn twenty times over five winters
//  and a t-shirt worn twenty times since March are the same number and
//  opposite facts. So the facet carries both axes that DO exist — how
//  many times (`wearCounts`) and how recently (`wearRecency`) — ANDed
//  together the way any two facets are, and every label states a count or
//  a date range and never a rate.
//
//  IT IS NOT A DEAD CONTROL TODAY, AND THAT WAS CHECKED RATHER THAN
//  ASSUMED. Marking a garment worn has shipped: the item-detail action row
//  increments `wear_count` and sets `last_worn_at` on the row, optimistic
//  and rolled back on failure (docs/03-progress.md, P3-CLOSET-09, Done).
//  Wear data is thin, not absent. Where it genuinely is absent — a closet
//  in which nothing has ever been marked worn — `ClosetFilterOptions`
//  drops the whole facet, because there every band matches nothing or
//  everything and none of them can narrow anything.
//
//  BRAND AND COLOUR ARE FREE TEXT, SO THEY MATCH ON A FOLDED KEY.
//  `closet_items.brand` and `.primary_color` are text columns and this app
//  deliberately never closed either vocabulary (see
//  `Components/ClosetColorPicker.swift` for why the colour field takes
//  anything). So "A.P.C.", "a.p.c." and "apc" arrive as three strings for
//  one brand, and matching them literally would offer the user three
//  chips that each hide two thirds of his jackets. `ClosetFilterText.key`
//  folds case, accents and punctuation away, and it is the folded key —
//  never the typed spelling — that this type stores and compares.
//
//  CHEAP ENOUGH FOR EVERY KEYSTROKE, WHICH IS THE SECOND CRITERION.
//  "Clearing filters returns to the unfiltered view without a full screen
//  reload flash" is satisfied by construction rather than by animation
//  tuning: an empty filter set returns the very array it was handed, and a
//  non-empty one is a single `filter` over set lookups on an array the
//  screen is already holding. Nothing here fetches, and nothing here can
//  put the screen back through a loading state.
//

import Foundation

// MARK: - Free-text folding

/// Folds a free-text garment field to the key that two spellings of the
/// same thing have to share.
///
/// Case, accents and punctuation all go, and so does every space: "A.P.C."
/// and "apc" fold to `apc`, "Hermès" and "Hermes" to `hermes`, "Forest
/// Green" and "forest green" to `forestgreen`. Whitespace is removed
/// rather than collapsed because the only difference between "forest
/// green" and "forestgreen" is a typing habit.
///
/// It deliberately does NOT use `AstraGarmentColor`'s last-word rule.
/// That rule exists to find a SWATCH for a name and is right for that —
/// "tobacco brown" is a brown — but as a grouping rule it would fold
/// "sky blue" and "navy blue" into one filter value called blue, which
/// would hand the user a chip that cannot distinguish two garments he can
/// see are different colours.
public enum ClosetFilterText {

    /// The folded key for a free-text value, or `nil` when there is no
    /// value there at all.
    ///
    /// `nil` covers both a missing field and a field holding only spaces
    /// or punctuation, which is the same fact one keystroke apart — a
    /// brand recorded as `"  "` is not a brand, and offering it as a chip
    /// labelled with nothing would be a control the user cannot read.
    public static func key(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let folded = raw.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
        let alphanumerics = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        guard !alphanumerics.isEmpty else { return nil }
        return String(String.UnicodeScalarView(alphanumerics))
    }

    /// The spelling shown on a chip: the user's own text, trimmed and
    /// nothing else. Case is his, not ours — a man who wrote "A.P.C."
    /// should not be shown "apc" back.
    public static func displayForm(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Wear count bands

/// How many times a garment has been marked worn, in bands.
///
/// Bands rather than a slider: `wear_count` is a small integer for most of
/// a wardrobe and a slider over 0-40 would ask the user to choose a
/// boundary he has no basis for. Bands also survive the thin data this
/// column carries today without lying about it — "Not worn yet" is a real,
/// useful reading of a zero, where a slider sitting at zero is not.
///
/// Every label states a COUNT. None of them says "often", "rarely" or
/// anything else that implies a rate, because a rate is exactly what this
/// column cannot support (see this file's header).
///
/// Not a persisted type: there is no Postgres enum behind it, nothing
/// encodes it, and the raw values exist only to give each band a stable
/// identifier for accessibility and `ForEach`.
public enum ClosetWearBand: String, CaseIterable, Identifiable, Sendable {
    case notWornYet
    case onceOrTwice
    case threeToNine
    case tenOrMore

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .notWornYet: String(localized: "Not worn yet", comment: "Wear-count filter band")
        case .onceOrTwice: String(localized: "Worn once or twice", comment: "Wear-count filter band")
        case .threeToNine: String(localized: "Worn 3 to 9 times", comment: "Wear-count filter band")
        case .tenOrMore: String(localized: "Worn 10 times or more", comment: "Wear-count filter band")
        }
    }

    /// Whether a garment's wear count falls in this band.
    ///
    /// The bands are contiguous and cover every integer, so a garment is
    /// always in exactly one — which is what makes selecting several of
    /// them an OR the user can predict. `.notWornYet` takes anything at or
    /// below zero rather than exactly zero: a negative count can only be
    /// bad data, and silently belonging to no band at all would drop the
    /// garment out of every wear filter with nothing on screen to explain
    /// why.
    public func contains(wearCount: Int) -> Bool {
        switch self {
        case .notWornYet: wearCount <= 0
        case .onceOrTwice: wearCount >= 1 && wearCount <= 2
        case .threeToNine: wearCount >= 3 && wearCount <= 9
        case .tenOrMore: wearCount >= 10
        }
    }
}

// MARK: - Wear recency windows

/// How recently a garment was last worn.
///
/// The axis `wearCount` cannot supply: twenty wears means one thing on a
/// coat bought in 2019 and another on a shirt bought in March, and
/// `last_worn_at` is the only column that tells those apart.
///
/// The windows are fixed-length spans, not calendar months. A calendar
/// month needs a time zone this model does not carry, and the difference
/// between "30 days" and "one calendar month" cannot change which garments
/// a man is looking for.
public enum ClosetWearRecency: String, CaseIterable, Identifiable, Sendable {
    case withinMonth
    case oneToSixMonths
    case longerAgo

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .withinMonth: String(localized: "Worn in the last month", comment: "Wear-recency filter band")
        case .oneToSixMonths: String(localized: "Worn 1 to 6 months ago", comment: "Wear-recency filter band")
        case .longerAgo: String(localized: "Last worn over 6 months ago", comment: "Wear-recency filter band")
        }
    }

    /// 30 days. Named rather than inlined so the two comparisons below
    /// cannot drift apart into overlapping windows.
    private static let monthInDays: Double = 30

    /// 182 days — half of 365, rounded down.
    private static let sixMonthsInDays: Double = 182

    private static let secondsPerDay: Double = 86_400

    /// Whether a garment's last-worn date falls in this window.
    ///
    /// A garment that has never been worn matches NO window, rather than
    /// falling into `.longerAgo`. "Last worn over 6 months ago" is a
    /// statement about a date, and a garment with no date has not been
    /// worn a long time ago — it has not been worn. That reading is
    /// `ClosetWearBand.notWornYet`'s job, and letting both facets answer
    /// it would give the same garments two different homes. It is also the
    /// same rule every other optional field in this file follows: nothing
    /// recorded means nothing matches.
    ///
    /// A date in the future can only be clock skew or bad data. It lands
    /// in `.withinMonth`, which is the least surprising of the available
    /// wrong answers — the garment shows up under "worn recently", where
    /// its own date is on screen for the user to see.
    public func contains(lastWornAt: Date?, asOf now: Date) -> Bool {
        guard let lastWornAt else { return false }
        let days = now.timeIntervalSince(lastWornAt) / Self.secondsPerDay
        switch self {
        case .withinMonth: return days < Self.monthInDays
        case .oneToSixMonths: return days >= Self.monthInDays && days < Self.sixMonthsInDays
        case .longerAgo: return days >= Self.sixMonthsInDays
        }
    }
}

// MARK: - The filter set

/// The eight §6.14 facets as a value.
///
/// `Sendable` and nonisolated on purpose, like `ClosetMetrics` beside it:
/// this is a value applied to values, holds no view or view-model state,
/// and can therefore run on whichever actor happens to be holding the
/// array. Only the view model that owns one is `@MainActor`.
public struct ClosetFilters: Equatable, Sendable {

    /// Spec §6.14 "Category". The one non-optional facet — every garment
    /// has a category, so this is the only facet that cannot exclude a
    /// garment for having nothing on file.
    public var categories: Set<ClothingCategory> = []

    /// Spec §6.14 "Color", as FOLDED KEYS (`ClosetFilterText.key`), never
    /// as typed spellings. Matches a garment on its primary colour or any
    /// of its secondary colours: a man filtering for blue wants the
    /// blue-striped shirt too, and `secondary_colors` is where the app
    /// recorded that stripe.
    public var colors: Set<String> = []

    /// Spec §6.14 "Season", matched against `seasonality` literally.
    ///
    /// An all-year garment is NOT returned by a filter for Summer, though
    /// it is wearable in one. Folding `.allSeason` into every other season
    /// would make the facet asymmetric in a way the user cannot see —
    /// "Summer" would quietly mean "summer or all year" while "All year"
    /// kept meaning only itself — and the honest version of that query is
    /// two chips, which this facet already supports because values within
    /// it are ORed.
    public var seasons: Set<Season> = []

    /// Spec §6.14 "Brand", as folded keys for the reason `colors` is.
    public var brands: Set<String> = []

    /// Spec §6.14 "Condition".
    public var conditions: Set<ItemCondition> = []

    /// Spec §6.14 "Fit". The garment's own cut, which is what
    /// `closet_items.fit` records — not a statement about the person
    /// wearing it.
    public var fits: Set<ItemFit> = []

    /// Spec §6.14 "Availability".
    public var availability: Set<AvailabilityState> = []

    /// Half of spec §6.14 "Wear frequency": how many times.
    public var wearCounts: Set<ClosetWearBand> = []

    /// The other half: how recently. ANDed with `wearCounts`, so
    /// "worn 10 times or more" plus "worn in the last month" is the
    /// narrow, useful query rather than the union of two broad ones.
    public var wearRecency: Set<ClosetWearRecency> = []

    /// An empty filter set: everything through, nothing narrowed.
    public init() {}

    /// Whether nothing is narrowing at all.
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

    /// How many of the eight §6.14 facets are narrowing — the number on
    /// the header button's badge.
    ///
    /// FACETS, NOT VALUES. Three categories chosen is one facet, because
    /// the badge answers "how many different questions am I asking of my
    /// closet", and a badge reading 3 for one question would tell the user
    /// he has three things to go and turn off.
    ///
    /// Wear counts as ONE even though it is two properties. §6.14 lists
    /// eight filters and this type must not claim a ninth; the two wear
    /// properties are two axes of the single "wear frequency" facet the
    /// spec names, and the panel presents them under one heading.
    public var activeFacetCount: Int {
        var count = 0
        if !categories.isEmpty { count += 1 }
        if !colors.isEmpty { count += 1 }
        if !seasons.isEmpty { count += 1 }
        if !brands.isEmpty { count += 1 }
        if !conditions.isEmpty { count += 1 }
        if !fits.isEmpty { count += 1 }
        if !availability.isEmpty { count += 1 }
        if !wearCounts.isEmpty || !wearRecency.isEmpty { count += 1 }
        return count
    }

    /// Applies every active facet to a closet, as of now.
    ///
    /// The wall clock enters this type in exactly one place — here — and
    /// `apply(to:asOf:)` is the whole implementation, so tests pin the
    /// wear-recency windows against a fixed instant instead of against
    /// whenever the suite happens to run.
    public func apply(to items: [ClosetItem]) -> [ClosetItem] {
        apply(to: items, asOf: .now)
    }

    /// Applies every active facet to a closet, as of a given instant.
    ///
    /// RETURNS THE ARRAY ITSELF WHEN NOTHING IS ACTIVE. Not a copy, not a
    /// re-derivation: the same value, so clearing the last facet puts the
    /// screen back on the identical array it was already rendering. That
    /// is the second acceptance criterion — "clearing filters returns to
    /// the unfiltered view without a full screen reload flash" — held by
    /// construction rather than by an animation, and it is why nothing in
    /// this file can trigger a fetch or a `.loading` state.
    public func apply(to items: [ClosetItem], asOf now: Date) -> [ClosetItem] {
        guard !isEmpty else { return items }
        return items.filter { matches($0, asOf: now) }
    }

    /// Turns every facet off.
    public mutating func clear() {
        self = ClosetFilters()
    }

    /// Whether one garment survives every active facet.
    ///
    /// Split into four by the KIND of field each facet reads, rather than
    /// written as one long chain. Partly so no single function carries
    /// nine branches, and partly because the four groups behave
    /// differently in ways worth keeping apart: the first three fields are
    /// always recorded, the next two are optional enums, the next two are
    /// free text that has to be folded before it can be compared, and the
    /// last two are the only ones that need to know what time it is.
    ///
    /// `&&` short-circuits, so a garment is still rejected on the first
    /// group it fails — a 500-item closet with only a category filter on
    /// does one set lookup per garment and stops. Each facet's work is
    /// additionally guarded on that facet being active, which is what
    /// keeps the free-text facets from folding colour strings for a filter
    /// set that never mentions colour.
    private func matches(_ item: ClosetItem, asOf now: Date) -> Bool {
        matchesAlwaysRecordedFacets(item)
            && matchesOptionalEnumFacets(item)
            && matchesFreeTextFacets(item)
            && matchesWearFacets(item, asOf: now)
    }

    /// Category, season and availability: fields every garment has.
    private func matchesAlwaysRecordedFacets(_ item: ClosetItem) -> Bool {
        if !categories.isEmpty, !categories.contains(item.category) {
            return false
        }
        // `seasonality` is an array and can be empty, which is the one
        // "always recorded" field that can still be absent — an empty one
        // matches no season, per this file's exclusion rule.
        if !seasons.isEmpty, !item.seasonality.contains(where: { seasons.contains($0) }) {
            return false
        }
        if !availability.isEmpty, !availability.contains(item.availabilityState) {
            return false
        }
        return true
    }

    /// Condition and cut: optional, so absent means excluded.
    private func matchesOptionalEnumFacets(_ item: ClosetItem) -> Bool {
        if !conditions.isEmpty {
            guard let condition = item.condition, conditions.contains(condition) else { return false }
        }
        if !fits.isEmpty {
            guard let fit = item.fit, fits.contains(fit) else { return false }
        }
        return true
    }

    /// Brand and colour: free text, compared on the folded key.
    private func matchesFreeTextFacets(_ item: ClosetItem) -> Bool {
        if !brands.isEmpty {
            guard let brand = ClosetFilterText.key(item.brand), brands.contains(brand) else { return false }
        }
        if !colors.isEmpty, !matchesColor(item) {
            return false
        }
        return true
    }

    /// The two axes of the one facet that needs to know the date.
    private func matchesWearFacets(_ item: ClosetItem, asOf now: Date) -> Bool {
        if !wearCounts.isEmpty, !wearCounts.contains(where: { $0.contains(wearCount: item.wearCount) }) {
            return false
        }
        if !wearRecency.isEmpty,
           !wearRecency.contains(where: { $0.contains(lastWornAt: item.lastWornAt, asOf: now) }) {
            return false
        }
        return true
    }

    /// Primary colour first, then the secondaries.
    ///
    /// Not built into a `Set` per garment: the closet is one man's
    /// wardrobe and a garment carries a handful of colour words, so
    /// folding each one as it is checked and stopping at the first hit
    /// does less work than allocating a set per garment per keystroke.
    private func matchesColor(_ item: ClosetItem) -> Bool {
        if let primary = ClosetFilterText.key(item.primaryColor), colors.contains(primary) {
            return true
        }
        return item.secondaryColors.contains { word in
            guard let key = ClosetFilterText.key(word) else { return false }
            return colors.contains(key)
        }
    }
}
