//
//  ClosetFilterPanelView.swift
//  AstraStyle
//
//  Spec §6.14's filter panel. Sets the values in a `ClosetFilters`; every
//  question about what those values MEAN is answered in
//  `Models/ClosetFilters.swift`, and which of them this closet can offer is
//  answered in `Models/ClosetFilterOptions.swift`. Nothing is computed here.
//
//  EIGHT FACETS IS TOO MANY TO LAY OUT FLAT, SO THEY ARE NOT.
//  Rendered as chip clouds one after another, §6.14's list is roughly sixty
//  chips — a wall a man scrolls past without reading, and one that gets
//  worse rather than better at accessibility text sizes, where each cloud
//  grows to several screens on its own. Two alternatives were considered.
//  A pushed screen per facet buries every choice one tap deeper and hides
//  the panel's most important fact — what is already on — behind
//  navigation. A flat list with a "show more" per facet is the wall again
//  with extra controls in it.
//
//  So: eight collapsed headings, and a summary above them. Closed, the
//  whole panel is a legible table of contents that fits on one screen even
//  at large type, and each heading carries its own selection underneath it
//  so scrolling past a closed section still tells you what it is doing.
//  Open, one facet at a time, it is a normal chip cloud in
//  `AstraWrappingHStack` — which wraps rather than scrolling sideways for
//  the reason that component was written.
//
//  A section starts OPEN when it already carries a selection, because the
//  first question a returning user has is "what did I turn on". When
//  nothing is on there is nothing to answer, so the first available facet
//  opens instead — an accordion with every row shut reads as inert, and one
//  open section shows what a heading contains without the user having to
//  guess.
//
//  WHAT IS ON, AT A GLANCE, AND REVERSIBLE ONE FACET AT A TIME.
//  The summary at the top is one row per narrowing: the facet's name, its
//  chosen values joined by the word "or", and a Clear for that row alone.
//  It is where both operators become visible without a legend — values
//  inside a row read as alternatives, rows stack as conditions — and it
//  means undoing one wrong tap never costs the other seven facets.
//
//  "Clear all" sits in the header as a tertiary text action and appears
//  only when there is something to clear, so it is never the loudest thing
//  on screen and never a control that does nothing (spec §22).
//
//  THE PANEL APPLIES AS YOU TAP; THE BUTTON ONLY CLOSES IT.
//  `filters` is a binding, so every toggle lands on the closet behind the
//  sheet immediately. There is no Apply step and no draft to lose, which is
//  what makes the second acceptance criterion — clearing filters without a
//  reload flash — true of turning them ON as well: the screen behind is
//  re-derived from an array it already holds, never re-fetched. The primary
//  action's job is therefore to state the result and get out of the way,
//  which is why it is labelled with the count rather than with "Apply".
//
//  A COMBINATION THAT MATCHES NOTHING IS SAID OUT LOUD, HERE, BEFORE THE
//  USER LEAVES. `ClosetFilterOptions` removes values no garment carries,
//  but facets are independent — blue tops in a closet with no blue tops is
//  still reachable, and no per-facet rule can prevent that without
//  recomputing every chip's count on every tap (that trade is argued in
//  `ClosetFilterOptions`'s header). So the panel says so where the user can
//  still act on it: the action bar names the empty result and the primary
//  action stops claiming it will show anything.
//
//  NO NAVIGATION STACK AND NO TITLE BAR. The screen states its own title
//  editorially, the way the Closet does, and a `navigationTitle` would say
//  "Filters" twice. The drag indicator is made visible instead, so the
//  sheet's own dismissal is an affordance the user can see rather than a
//  gesture he has to know.
//

import SwiftUI

// MARK: - The eight headings

/// The §6.14 facets, in the order the spec lists them.
///
/// A type rather than eight repeated blocks, so the panel's structure —
/// section, label, selection summary, expansion state — is written once and
/// each facet only supplies its own chips.
private enum ClosetFilterFacet: String, CaseIterable, Identifiable {
    case category
    case color
    case season
    case brand
    case condition
    case fit
    case availability
    case wear

    var id: String { rawValue }

    /// The heading.
    var title: String {
        switch self {
        case .category: String(localized: "Category", comment: "Closet filter heading")
        case .color: String(localized: "Colour", comment: "Closet filter heading")
        case .season: String(localized: "Season", comment: "Closet filter heading")
        case .brand: String(localized: "Brand", comment: "Closet filter heading")
        case .condition: String(localized: "Condition", comment: "Closet filter heading")
        case .fit: String(localized: "Cut", comment: "Closet filter heading for how a garment is cut")
        case .availability: String(localized: "Availability", comment: "Closet filter heading")
        case .wear: String(localized: "Wear", comment: "Closet filter heading covering how often and how recently a piece is worn")
        }
    }

    /// What VoiceOver announces before reading a facet's chips, so a group
    /// of loose words is heard as a choice between something (spec §19).
    ///
    /// Deliberately the same string as the visible heading rather than a
    /// friendlier paraphrase. An earlier draft announced "Who made it" over
    /// a heading reading "Brand"; two names for one control is how a
    /// non-visual user and a sighted user end up unable to describe the
    /// same screen to each other. The wear facet is the exception and
    /// supplies its own, because its two sub-headings — "How often", "How
    /// recently" — do not say what they are about on their own.
    var groupLabel: String { title }
}

// MARK: - The panel

/// The filter panel, presented as a sheet over the Closet.
struct ClosetFilterPanelView: View {

    /// Bound, not copied: every toggle applies to the closet behind the
    /// sheet as it happens. See this file's header for why there is no
    /// Apply step.
    @Binding private var filters: ClosetFilters

    /// What this closet can offer. Derived by the presenter from the array
    /// the screen is already showing — see `ClosetFilterOptions`'s header
    /// for which array that should be.
    private let options: ClosetFilterOptions

    /// How many pieces a given filter set would leave on screen.
    ///
    /// A closure rather than the items themselves, so the panel never holds
    /// a closet and cannot be tempted to derive anything from one. The
    /// presenter is expected to answer for the same scope the screen is in
    /// — search included — because this number is a promise about what the
    /// user will see when the sheet closes.
    private let matchCount: (ClosetFilters) -> Int

    private let onDone: () -> Void

    /// Which headings are open. Seeded once in `init`; after that it is the
    /// user's, and a facet he closed stays closed even as he keeps tapping
    /// chips elsewhere.
    @State private var expandedFacets: Set<ClosetFilterFacet>

    init(
        filters: Binding<ClosetFilters>,
        options: ClosetFilterOptions,
        matchCount: @escaping (ClosetFilters) -> Int,
        onDone: @escaping () -> Void
    ) {
        _filters = filters
        self.options = options
        self.matchCount = matchCount
        self.onDone = onDone
        _expandedFacets = State(
            initialValue: Self.initialExpansion(filters: filters.wrappedValue, options: options)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                header
                activeSummary
                facetSections
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { actionBar }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Header

extension ClosetFilterPanelView {

    private var header: some View {
        // Present only when there is something to undo. A "Clear all" above
        // an untouched panel is the dead control §22 rules out, and it is
        // the one control here that would be easiest to leave permanently
        // on screen out of symmetry.
        let clearAllTitle: String? = filters.isEmpty
            ? nil
            : String(localized: "Clear all", comment: "Turns every closet filter off")
        let clearAllAction: (() -> Void)? = filters.isEmpty ? nil : { clearAll() }

        return VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            AstraSectionHeader(
                title: String(localized: "Filters", comment: "Title of the closet filter panel"),
                actionTitle: clearAllTitle,
                action: clearAllAction
            )

            // The one place the two operators are stated in words. Every
            // other statement of them in this panel is structural — values
            // joined by "or", facets stacked as rows — and structure alone
            // is a convention the user has to already know.
            Text(String(
                localized: "Pick as many as you like. Within a heading, any match counts. Across headings, all of them have to.",
                comment: "Explains that filter values within one heading are alternatives and headings combine"
            ))
            .astraText(.caption)
            .foregroundStyle(AstraColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
    }

    private func clearAll() {
        filters.clear()
        // The same haptic archiving uses: this undoes work the user did,
        // and a selection tick would understate it.
        AstraHaptics.warning()
    }
}

// MARK: - What is on now

extension ClosetFilterPanelView {

    /// One row per narrowing, or nothing at all when nothing is on.
    ///
    /// Deliberately absent rather than replaced with "no filters yet": the
    /// panel below already says what filters are, and an empty state above
    /// it would push the first heading off the screen to tell the user
    /// something the screen is already showing.
    @ViewBuilder
    private var activeSummary: some View {
        let rows = summaryRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                ForEach(rows) { row in
                    summaryRow(row)
                    if row.id != rows.last?.id {
                        // An explicit token rule rather than `Divider()`,
                        // which draws the system separator colour and
                        // would be the one hardcoded colour on the screen.
                        Rectangle()
                            .fill(AstraColor.divider)
                            .frame(height: 1)
                    }
                }
            }
            .padding(AstraSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .fill(AstraColor.backgroundSecondary)
            )
            .padding(.horizontal, AstraSpacing.pagePadding)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(String(
                localized: "Filters currently on",
                comment: "VoiceOver label for the summary of active closet filters"
            )))
        }
    }

    private func summaryRow(_ row: ClosetFilterSummaryRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AstraSpacing.sm) {
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(row.title)
                    .astraText(.micro)
                    .foregroundStyle(AstraColor.textMuted)
                Text(row.values)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(String(localized: "Clear", comment: "Turns one closet filter heading off"), action: row.clear)
                .buttonStyle(.astraTertiary)
                .accessibilityLabel(Text(String(
                    format: String(localized: "Clear the %@ filter", comment: "VoiceOver label for clearing one filter heading; %@ is the heading"),
                    row.title
                )))
        }
    }
}

// MARK: - The eight sections

extension ClosetFilterPanelView {

    @ViewBuilder
    private var facetSections: some View {
        let facets = ClosetFilterFacet.allCases.filter { Self.hasOptions($0, in: options) }
        if facets.isEmpty {
            nothingToFilterNotice
        } else {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                ForEach(facets) { facet in
                    section(facet)
                }
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
        }
    }

    private func section(_ facet: ClosetFilterFacet) -> some View {
        DisclosureGroup(isExpanded: expansion(facet)) {
            chips(for: facet)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AstraSpacing.xs)
        } label: {
            sectionLabel(facet)
        }
        // The chevron is an icon, so it takes the plain champagne fill
        // rather than the text token (spec §3 / docs/07).
        .tint(AstraColor.accentChampagne)
    }

    /// The heading, plus what it is doing while it is shut.
    ///
    /// The selection line is drawn ONLY while the section is collapsed.
    /// Open, the same information is already on screen and more precisely
    /// — the chosen chips carry checkmarks — and repeating it above them
    /// would be the panel saying the same thing twice in two formats.
    private func sectionLabel(_ facet: ClosetFilterFacet) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(facet.title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)

            if !expandedFacets.contains(facet), let summary = selectedValueSummary(facet) {
                Text(summary)
                    // Champagne as TEXT, so the accessible token (spec §19).
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AstraSpacing.xs)
    }

    /// One heading's chips.
    ///
    /// Every case is the same call because every facet behaves the same
    /// way; only the values and the property they land in differ. Written
    /// out nine times instead, this is where one facet quietly becomes
    /// single-select, or loses its accessibility label, and nobody notices
    /// because the other eight are right.
    @ViewBuilder
    private func chips(for facet: ClosetFilterFacet) -> some View {
        switch facet {
        case .category: chipGroup(facet, options.categories, \.categories)
        // Colour is the only facet whose values are things you can see, so
        // it is the only one that draws swatches — and only where this
        // build knows the word, never as a rectangle it guessed.
        case .color: chipGroup(facet, options.colors, \.colors, showsSwatches: true)
        case .season: chipGroup(facet, options.seasons, \.seasons)
        case .brand: chipGroup(facet, options.brands, \.brands)
        case .condition: chipGroup(facet, options.conditions, \.conditions)
        case .fit: chipGroup(facet, options.fits, \.fits)
        case .availability: chipGroup(facet, options.availability, \.availability)
        case .wear: wearChips
        }
    }

    /// A chip group over an enum facet, whose values are what the filter
    /// set stores.
    private func chipGroup<Value: ClosetFilterChipValue>(
        _ facet: ClosetFilterFacet,
        _ values: [Value],
        _ selection: WritableKeyPath<ClosetFilters, Set<Value>>,
        groupLabel: String? = nil,
        identifierPrefix: String? = nil
    ) -> some View {
        ClosetFilterChipGroup(
            values: values,
            isSelected: { filters[keyPath: selection].contains($0) },
            toggle: { toggle($0, in: selection) },
            groupLabel: groupLabel ?? facet.groupLabel,
            identifierPrefix: identifierPrefix ?? facet.rawValue
        )
    }

    /// A chip group over a free-text facet, where the chip carries a
    /// spelling and the filter set stores the folded key behind it.
    private func chipGroup(
        _ facet: ClosetFilterFacet,
        _ values: [ClosetFilterValue],
        _ selection: WritableKeyPath<ClosetFilters, Set<String>>,
        showsSwatches: Bool = false
    ) -> some View {
        ClosetFilterChipGroup(
            values: values,
            isSelected: { filters[keyPath: selection].contains($0.key) },
            toggle: { toggle($0.key, in: selection) },
            groupLabel: facet.groupLabel,
            identifierPrefix: facet.rawValue,
            showsSwatches: showsSwatches
        )
    }

    /// The one facet with two axes, laid out as two labelled lines.
    ///
    /// Kept under a single §6.14 heading rather than split into a ninth
    /// facet, because "how often" and "how recently" are two readings of
    /// one question and the spec names one filter. They compose the way any
    /// two facets do — both must match — which is stated under them rather
    /// than left for the user to discover by getting an empty result.
    @ViewBuilder
    private var wearChips: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            if !options.wearCounts.isEmpty {
                wearSubgroup(
                    title: String(localized: "How often", comment: "Sub-heading over the wear-count filter chips"),
                    // Says what the number is, because the §6.14 heading
                    // says "frequency" and this is not one — there is no
                    // ownership date to divide by (see `ClosetFilters`).
                    note: String(
                        localized: "Counts, not rates — how many times a piece has been marked worn.",
                        comment: "Clarifies that the wear filter counts wears rather than measuring a rate"
                    )
                ) {
                    chipGroup(
                        .wear, options.wearCounts, \.wearCounts,
                        groupLabel: String(localized: "Worn how often", comment: "VoiceOver group label for the wear-count chips"),
                        identifierPrefix: "wearCount"
                    )
                }
            }

            if !options.wearRecency.isEmpty {
                wearSubgroup(
                    title: String(localized: "How recently", comment: "Sub-heading over the wear-recency filter chips"),
                    note: options.wearCounts.isEmpty ? nil : String(
                        localized: "Pick from both lines and a piece has to match both.",
                        comment: "Explains that the two wear filters combine"
                    )
                ) {
                    chipGroup(
                        .wear, options.wearRecency, \.wearRecency,
                        groupLabel: String(localized: "Worn how recently", comment: "VoiceOver group label for the wear-recency chips"),
                        identifierPrefix: "wearRecency"
                    )
                }
            }
        }
    }

    private func wearSubgroup(
        title: String,
        note: String?,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(title)
                .astraText(.micro)
                .foregroundStyle(AstraColor.textMuted)
            content()
            if let note {
                Text(note)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Shown when the closet cannot offer a single filter value.
    ///
    /// Reachable, and not only for an empty closet: five navy t-shirts of
    /// one brand, condition and cut differ in nothing, so every facet is
    /// dropped. Saying that plainly beats an empty sheet, which reads as a
    /// screen that failed to load.
    private var nothingToFilterNotice: some View {
        Text(String(
            localized: "There's nothing to narrow yet. Headings appear here as your closet takes on pieces that differ — in kind, colour, brand, or how much they get worn.",
            comment: "Shown in the filter panel when the closet offers no filter values"
        ))
        .astraText(.body)
        .foregroundStyle(AstraColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AstraSpacing.pagePadding)
    }
}

// MARK: - Action bar

extension ClosetFilterPanelView {

    /// Pinned to the bottom, opaque, and always showing the result.
    ///
    /// The count is the panel's whole feedback loop: filters apply as they
    /// are tapped, so this number moves under the user's finger and tells
    /// him what the sheet is about to reveal without him having to close it
    /// to find out.
    private var actionBar: some View {
        let count = matchCount(filters)

        return VStack(spacing: AstraSpacing.xs) {
            if count == 0 {
                Text(String(
                    localized: "Nothing in your closet matches all of these. Clear one heading above to widen it.",
                    comment: "Shown when the chosen closet filters leave no pieces"
                ))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
            }

            // Always does the same real thing — close the sheet — so it is
            // never disabled and never dead (spec §22). Only its label
            // changes, because "Show 0 pieces" would be a promise the
            // screen behind cannot keep.
            Button(primaryTitle(for: count), action: onDone)
                .buttonStyle(.astraPrimary)
                .accessibilityIdentifier("closet.filter.done")
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
        .padding(.vertical, AstraSpacing.md)
        .background(AstraColor.backgroundPrimary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AstraColor.divider)
                .frame(height: 1)
        }
    }

    /// The singular is spelled out rather than formatted, because "Show 1
    /// pieces" is what one plural format string produces here.
    private func primaryTitle(for count: Int) -> String {
        switch count {
        case 0: String(localized: "Close", comment: "Closes the filter panel when the filters match nothing")
        case 1: String(localized: "Show 1 piece", comment: "Primary action of the filter panel when one piece matches")
        default: String(format: String(localized: "Show %d pieces", comment: "Primary action of the filter panel; %d is how many pieces match"), count)
        }
    }
}

// MARK: - Selection state

extension ClosetFilterPanelView {

    private func expansion(_ facet: ClosetFilterFacet) -> Binding<Bool> {
        Binding(
            get: { expandedFacets.contains(facet) },
            set: { isOpen in expandedFacets = isOpen ? expandedFacets.union([facet]) : expandedFacets.subtracting([facet]) }
        )
    }

    /// Turns one value on or off inside one facet.
    ///
    /// Key-pathed rather than written out nine times: the toggle is the
    /// same gesture everywhere, and nine copies of it is nine chances for
    /// one facet to quietly become single-select.
    ///
    /// `formSymmetricDifference` rather than a contains/remove/insert
    /// dance, because that dance is where an "off" that only ever turns
    /// things on comes from.
    private func toggle<Value: Hashable>(_ value: Value, in facet: WritableKeyPath<ClosetFilters, Set<Value>>) {
        filters[keyPath: facet].formSymmetricDifference([value])
        AstraHaptics.selection()
    }

    fileprivate static func hasOptions(_ facet: ClosetFilterFacet, in options: ClosetFilterOptions) -> Bool {
        switch facet {
        case .category: !options.categories.isEmpty
        case .color: !options.colors.isEmpty
        case .season: !options.seasons.isEmpty
        case .brand: !options.brands.isEmpty
        case .condition: !options.conditions.isEmpty
        case .fit: !options.fits.isEmpty
        case .availability: !options.availability.isEmpty
        case .wear: !options.wearCounts.isEmpty || !options.wearRecency.isEmpty
        }
    }

    private static func hasSelection(_ facet: ClosetFilterFacet, in filters: ClosetFilters) -> Bool {
        switch facet {
        case .category: !filters.categories.isEmpty
        case .color: !filters.colors.isEmpty
        case .season: !filters.seasons.isEmpty
        case .brand: !filters.brands.isEmpty
        case .condition: !filters.conditions.isEmpty
        case .fit: !filters.fits.isEmpty
        case .availability: !filters.availability.isEmpty
        case .wear: !filters.wearCounts.isEmpty || !filters.wearRecency.isEmpty
        }
    }

    /// Which headings are open the moment the sheet appears.
    ///
    /// Everything already narrowing, because that is the question a
    /// returning user opens this panel with. Failing that, the first
    /// heading that has anything in it — see this file's header for why one
    /// section is open rather than none.
    private static func initialExpansion(
        filters: ClosetFilters,
        options: ClosetFilterOptions
    ) -> Set<ClosetFilterFacet> {
        let offered = ClosetFilterFacet.allCases.filter { hasOptions($0, in: options) }
        let narrowing = offered.filter { hasSelection($0, in: filters) }
        return narrowing.isEmpty ? Set(offered.prefix(1)) : Set(narrowing)
    }
}

// MARK: - Summarising what is on

/// One line of the summary card: a facet that is narrowing, what it is
/// narrowing to, and the control that turns it off.
private struct ClosetFilterSummaryRow: Identifiable {
    let id: String
    let facet: ClosetFilterFacet
    let title: String
    let values: String
    let clear: () -> Void
}

extension ClosetFilterPanelView {

    /// Every narrowing currently in force, in §6.14's order.
    ///
    /// Wear contributes up to TWO rows, one per axis, because they are
    /// ANDed with each other and a single row joining them with "or" would
    /// state the opposite of what the filter does.
    private var summaryRows: [ClosetFilterSummaryRow] {
        [
            row(.category, values: Self.labels(of: filters.categories)) { filters.categories = [] },
            row(.color, values: Self.labels(of: filters.colors, offering: options.colors)) { filters.colors = [] },
            row(.season, values: Self.labels(of: filters.seasons)) { filters.seasons = [] },
            row(.brand, values: Self.labels(of: filters.brands, offering: options.brands)) { filters.brands = [] },
            row(.condition, values: Self.labels(of: filters.conditions)) { filters.conditions = [] },
            row(.fit, values: Self.labels(of: filters.fits)) { filters.fits = [] },
            row(.availability, values: Self.labels(of: filters.availability)) { filters.availability = [] },
            row(
                .wear,
                id: "wearCount",
                title: String(localized: "Worn how often", comment: "Summary row heading for the wear-count filter"),
                values: Self.labels(of: filters.wearCounts)
            ) { filters.wearCounts = [] },
            row(
                .wear,
                id: "wearRecency",
                title: String(localized: "Worn how recently", comment: "Summary row heading for the wear-recency filter"),
                values: Self.labels(of: filters.wearRecency)
            ) { filters.wearRecency = [] }
        ].compactMap { $0 }
    }

    /// What a collapsed heading says it is doing.
    private func selectedValueSummary(_ facet: ClosetFilterFacet) -> String? {
        let stated = summaryRows.filter { $0.facet == facet }.map(\.values)
        guard !stated.isEmpty else { return nil }
        // Only the wear facet can produce two, and its two are ANDed.
        return stated.joined(separator: String(
            localized: " and ",
            comment: "Joins the two wear filters in a collapsed heading's summary, where a piece has to match both"
        ))
    }

    /// One summary row, or `nil` when that facet is not narrowing.
    ///
    /// Returning `nil` rather than having each call site test its own
    /// property first: nine `if !x.isEmpty` blocks around nine near-identical
    /// constructions is nine chances to test one property and clear another.
    private func row(
        _ facet: ClosetFilterFacet,
        id: String? = nil,
        title: String? = nil,
        values: [String],
        clear: @escaping () -> Void
    ) -> ClosetFilterSummaryRow? {
        guard !values.isEmpty else { return nil }
        return ClosetFilterSummaryRow(
            id: id ?? facet.rawValue,
            facet: facet,
            title: title ?? facet.title,
            values: Self.joinedWithOr(values),
            clear: {
                clear()
                // Undoing a narrowing, not making one — the same haptic
                // "Clear all" uses.
                AstraHaptics.warning()
            }
        )
    }

    /// The chosen values of an enum facet, in the enum's own order rather
    /// than in the order they were tapped, so the row reads the same way
    /// twice.
    private static func labels<Value>(of selected: Set<Value>) -> [String]
    where Value: ClosetFilterChipValue & CaseIterable {
        Value.allCases.filter { selected.contains($0) }.map(\.chipLabel)
    }

    /// The chosen values of a free-text facet, resolved back to spellings.
    ///
    /// A key with no offered value behind it is shown AS the key rather
    /// than dropped. It happens when the last garment carrying a brand is
    /// archived while the panel is open: the filter is still on and still
    /// narrowing, so a summary that quietly omitted it would leave the user
    /// with a Clear that appears to do nothing.
    private static func labels(of keys: Set<String>, offering values: [ClosetFilterValue]) -> [String] {
        var labels = values.filter { keys.contains($0.key) }.map(\.displayName)
        let offered = Set(values.map(\.key))
        labels.append(contentsOf: keys.subtracting(offered).sorted())
        return labels
    }

    /// Joins one facet's values the way the facet treats them.
    ///
    /// The separator carries the semantics, which is why it is a localised
    /// string with its spaces inside it rather than a hardcoded ", ":
    /// "Tops or Bottoms" states the OR that the code performs, and a comma
    /// would leave the user to guess between OR and AND.
    private static func joinedWithOr(_ values: [String]) -> String {
        values.joined(separator: String(
            localized: " or ",
            comment: "Joins the chosen values of one filter heading, any of which is a match"
        ))
    }
}

// MARK: - Chips

/// What a filter value has to be able to say for itself to become a chip.
///
/// A protocol rather than a pair of closures at nine call sites: the label
/// and the identifier of a value are properties OF that value, and passing
/// them in per section is how one facet ends up labelled from a different
/// source than the rest. Every conformance below is one line and points at
/// the `displayName` the domain already owns — this panel writes no labels
/// of its own, which is the rule that keeps "Autumn" from becoming "Fall"
/// on one screen out of nine.
private protocol ClosetFilterChipValue: Hashable {
    /// The user-facing label. Never written here.
    var chipLabel: String { get }
    /// A stable, non-localised suffix for the accessibility identifier, so
    /// a UI test targets a value rather than a translation.
    var chipIdentifier: String { get }
}

/// Every enum facet is `String`-backed and its raw value is already the
/// stable, non-localised name the identifier wants, so none of the seven
/// below has to state it.
extension ClosetFilterChipValue where Self: RawRepresentable, Self.RawValue == String {
    fileprivate var chipIdentifier: String { rawValue }
}

extension ClothingCategory: ClosetFilterChipValue { fileprivate var chipLabel: String { displayName } }
extension Season: ClosetFilterChipValue { fileprivate var chipLabel: String { displayName } }
extension ItemCondition: ClosetFilterChipValue { fileprivate var chipLabel: String { displayName } }
extension ItemFit: ClosetFilterChipValue { fileprivate var chipLabel: String { displayName } }
extension AvailabilityState: ClosetFilterChipValue { fileprivate var chipLabel: String { displayName } }
extension ClosetWearBand: ClosetFilterChipValue { fileprivate var chipLabel: String { displayName } }
extension ClosetWearRecency: ClosetFilterChipValue { fileprivate var chipLabel: String { displayName } }

extension ClosetFilterValue: ClosetFilterChipValue {
    fileprivate var chipLabel: String { displayName }
    /// The folded key, which is already lowercase and punctuation-free.
    fileprivate var chipIdentifier: String { key }
}

/// One facet's chips.
///
/// `AstraWrappingHStack` rather than a horizontal scroller, for the reason
/// that component exists: a sideways scroller hides its last options behind
/// a gesture with no affordance, and does it worst at the largest text
/// sizes — which is exactly where a filter panel has to keep working.
///
/// No cap on how many are shown, unlike the colour suggestions in the
/// add form. That list is a prompt beside a text field the user can type
/// into anyway; this one is the entire contents of a heading he opened on
/// purpose, and truncating it would hide the brand he came here for behind
/// a control that does not exist.
private struct ClosetFilterChipGroup<Value: ClosetFilterChipValue>: View {
    let values: [Value]
    let isSelected: (Value) -> Bool
    let toggle: (Value) -> Void
    /// Announced before the chips so VoiceOver says what they choose
    /// between, rather than reading a dozen loose words (spec §19).
    let groupLabel: String
    let identifierPrefix: String
    var showsSwatches = false

    var body: some View {
        AstraWrappingHStack(spacing: AstraSpacing.xs) {
            ForEach(values, id: \.self) { value in
                chip(for: value)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(groupLabel))
    }

    @ViewBuilder
    private func chip(for value: Value) -> some View {
        let identifier = "closet.filter.\(identifierPrefix).\(value.chipIdentifier)"
        if showsSwatches {
            ClosetFilterColorChip(name: value.chipLabel, isSelected: isSelected(value)) {
                toggle(value)
            }
            .accessibilityIdentifier(identifier)
        } else {
            AstraChip(value.chipLabel, isSelected: isSelected(value)) {
                toggle(value)
            }
            .accessibilityIdentifier(identifier)
        }
    }
}

/// A colour chip: the swatch, then the word.
///
/// Not `AstraChip`, and the reason is narrow — that component's leading
/// slot takes an SF Symbol, and a garment colour is not a symbol. The
/// alternative was a colour facet with no colour in it, which is the one
/// thing this facet should not be. Everything else about it is `AstraChip`
/// to the token: same capsule, same champagne fill and `textOnAccent` label
/// when selected, same checkmark so the state is never carried by colour
/// alone (spec §19), same 44 pt minimum. `ClosetColorTokenList` in the add
/// form is built the same way for the same reason.
///
/// The swatch itself comes from `ClosetColorSwatch`, so a word this build
/// has no swatch for draws NOTHING rather than a rectangle the app guessed
/// — and every swatch that is drawn carries the `divider` stroke that keeps
/// a bone or bright-white chip from disappearing into a light background.
private struct ClosetFilterColorChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AstraSpacing.xxs) {
                ClosetColorSwatch(name: name, size: AstraSpacing.sm)
                Text(name)
                    .astraText(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                }
            }
            .foregroundStyle(isSelected ? AstraColor.textOnAccent : AstraColor.textSecondary)
            .padding(.horizontal, AstraSpacing.md)
            .padding(.vertical, AstraSpacing.xs)
            .frame(minHeight: AstraSize.minTapTarget)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AstraColor.accentChampagne : AstraColor.backgroundSecondary)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : AstraColor.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .astraAnimation(AstraMotion.standard, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
    }
}

// MARK: - Previews

/// Holds the filter set the way the Closet will, so the previews exercise
/// the binding rather than a frozen value.
private struct ClosetFilterPanelPreview: View {
    let items: [ClosetItem]
    @State var filters = ClosetFilters()

    /// Two facets on, which is the state the first acceptance criterion
    /// describes: a category and a colour, intersected.
    static var twoFacets: ClosetFilters {
        var filters = ClosetFilters()
        filters.categories = [.top]
        filters.colors = ["navy", "olive"]
        return filters
    }

    var body: some View {
        ClosetFilterPanelView(
            filters: $filters,
            options: ClosetFilterOptions.derive(from: items),
            matchCount: { $0.apply(to: items).count },
            onDone: {}
        )
    }
}

#Preview("Nothing on yet") {
    ClosetFilterPanelPreview(items: SampleData.closetItems)
        .preferredColorScheme(.dark)
}

#Preview("Two facets narrowing") {
    ClosetFilterPanelPreview(
        items: SampleData.closetItems,
        filters: ClosetFilterPanelPreview.twoFacets
    )
    .preferredColorScheme(.dark)
}

#Preview("A closet with nothing to narrow") {
    ClosetFilterPanelPreview(items: Array(SampleData.closetItems.prefix(1)))
        .preferredColorScheme(.dark)
}
