//
//  ClosetMetricsRow.swift
//  AstraStyle
//
//  The metrics row from spec §6.14, sitting between the category tiles and
//  the closet grid. Renders a `ClosetMetrics` and does no arithmetic of its
//  own — every number and every "there is no number" decision is made in
//  `Features/Closet/Models/ClosetMetrics.swift`, which is where the
//  reasoning behind each of them is recorded.
//
//  IT MUST NOT DOMINATE THE PAGE.
//  It shares §6.14 with the header, eight category tiles, a view-mode
//  toggle and (once its panel exists) a filter button. So it is one card,
//  not five, and every figure sits at `title2` with a `micro` label rather
//  than at display weight: this is context for the grid below it, not the
//  subject of the screen.
//
//  LAYOUT AT LARGE DYNAMIC TYPE.
//  Five metrics do not fit across one row once the text grows, and the two
//  usual escapes are both unacceptable here. `lineLimit(1)` truncates a
//  number, which turns $12,480 into $12,4… and reports a different figure
//  from the one that was computed. `minimumScaleFactor` shrinks exactly the
//  text that the user enlarged Dynamic Type in order to read (spec §19).
//  So neither is used anywhere in this file: the number always renders in
//  full and always at the size it was asked for, and it is the COLUMN COUNT
//  that gives way — three, then two, then one, as the type grows. Every
//  string wraps rather than clipping, which is what `fixedSize` guarantees
//  inside a `LazyVGrid` whose rows would otherwise size to the first one.
//
//  A BLANK ALWAYS SAYS WHAT IT MEANS.
//  No metric ever renders "—", "0" or a spinner. Where there is no figure
//  there is a sentence in its place, in a visibly different style from a
//  figure (`callout` in `textSecondary`, not `title2` in `textPrimary`), so
//  a state is never mistaken for a value at a glance.
//

import SwiftUI

/// Column geometry for the metrics row.
///
/// A column COUNT keyed to the type size rather than a minimum tile width,
/// matching `ClosetGridMetrics` and for its stated reason: a fixed minimum
/// width is a hardcoded layout constant, and here it would additionally
/// squeeze the one thing that must not be squeezed. Growing text gets more
/// width, not less.
enum ClosetMetricsLayout {
    /// Three columns at ordinary text sizes; two once text is large; one at
    /// accessibility sizes past the second, where a single metric already
    /// fills the screen's width on its own.
    static func columnCount(for dynamicTypeSize: DynamicTypeSize) -> Int {
        if dynamicTypeSize >= .accessibility2 { return 1 }
        if dynamicTypeSize >= .xxLarge { return 2 }
        return 3
    }

    static func columns(for dynamicTypeSize: DynamicTypeSize) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: AstraSpacing.md, alignment: .topLeading),
            count: columnCount(for: dynamicTypeSize)
        )
    }
}

struct ClosetMetricsRow: View {

    private let metrics: ClosetMetrics

    /// Called with a `ClosetItem.id` when the most-worn or least-worn
    /// metric is tapped. Those two tiles are the only ones that name a
    /// specific garment, so they are the only ones that can lead anywhere;
    /// the presenter decides where.
    private let onSelectItem: (UUID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(metrics: ClosetMetrics, onSelectItem: @escaping (UUID) -> Void) {
        self.metrics = metrics
        self.onSelectItem = onSelectItem
    }

    var body: some View {
        AstraCard {
            LazyVGrid(
                columns: ClosetMetricsLayout.columns(for: dynamicTypeSize),
                alignment: .leading,
                spacing: AstraSpacing.lg
            ) {
                totalItemsTile
                estimatedValueTile
                averageCostPerWearTile
                mostWornTile
                leastWornTile
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Tiles

extension ClosetMetricsRow {

    /// One metric: a `micro` label, the figure or the sentence standing in
    /// for it, and any number of supporting lines beneath.
    ///
    /// `fixedSize(horizontal: false, vertical: true)` is what lets a long
    /// value wrap to as many lines as it needs inside a grid cell instead
    /// of being clipped to the height of its row.
    @ViewBuilder
    private func metricTile(
        label: String,
        details: [String] = [],
        @ViewBuilder value: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(label)
                .astraText(.micro)
                .foregroundStyle(AstraColor.textMuted)

            value()

            ForEach(details, id: \.self) { detail in
                Text(detail)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .topLeading)
    }

    /// A measured figure.
    private func figure(_ text: String) -> some View {
        Text(text)
            .astraText(.title2)
            .foregroundStyle(AstraColor.textPrimary)
    }

    /// A defined state standing in for a figure that does not exist. Set in
    /// a different style from `figure(_:)` deliberately — the difference
    /// between "this is your number" and "there is no number yet" has to be
    /// legible before the sentence is read.
    private func state(_ text: String) -> some View {
        Text(text)
            .astraText(.callout)
            .foregroundStyle(AstraColor.textSecondary)
    }

    // MARK: Total items

    private var totalItemsTile: some View {
        metricTile(
            label: String(localized: "Total items", comment: "Closet metrics label: how many garments the closet holds")
        ) {
            // `formatted()` rather than string interpolation so the
            // thousands separator follows the reader's locale.
            figure(metrics.totalItems.formatted())
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Estimated closet value

    private var estimatedValueTile: some View {
        metricTile(
            label: String(localized: "Estimated value", comment: "Closet metrics label: what the closet is worth"),
            details: estimatedValueDetails
        ) {
            if metrics.estimatedValue.hasAnyPrice {
                // One line per currency. Never a converted single figure —
                // there is no exchange rate on the device, and inventing
                // one would turn a real total into a fabricated one.
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    ForEach(metrics.estimatedValue.subtotals) { subtotal in
                        figure(subtotal.formattedAmount)
                    }
                }
            } else {
                state(String(localized: "No prices on file", comment: "Closet value is unknown because no garment has a purchase price"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The lines that keep "estimated" from being decorative.
    ///
    /// Coverage is stated on every path where the total is partial, because
    /// the total on its own is the misleading part: three priced pieces out
    /// of forty reads as a $400 wardrobe unless the sentence underneath
    /// says it is three pieces out of forty.
    private var estimatedValueDetails: [String] {
        let value = metrics.estimatedValue
        guard value.hasAnyPrice else {
            return [String(localized: "Add what you paid for a piece and this starts counting.", comment: "Closet value: how to make the figure exist")]
        }

        var lines: [String] = []
        if value.isComplete {
            lines.append(String(localized: "Every piece has a price on file.", comment: "Closet value covers the whole closet"))
        } else {
            lines.append(
                String(
                    localized: "From ^[\(value.pricedItemCount) piece](inflect: true) of \(value.itemCount). The rest have no price on file, so the real total is higher.",
                    comment: "Closet value covers only the garments that have a recorded price"
                )
            )
        }

        if value.spansMultipleCurrencies {
            lines.append(String(localized: "Kept apart by currency — Astra never converts between them.", comment: "Why the closet value is shown as more than one figure"))
        }
        return lines
    }
}

// MARK: - Average cost per wear

extension ClosetMetricsRow {

    private var averageCostPerWearTile: some View {
        metricTile(
            label: String(localized: "Average cost per wear", comment: "Closet metrics label: total spend divided by total wears"),
            details: averageCostPerWearDetails
        ) {
            switch metrics.averageCostPerWear {
            case .amount(let value, let currencyCode):
                // Routed through the existing formatter rather than a
                // second "/ wear" string: the sentence already has a
                // localisation key on the item detail screen, and two keys
                // for one sentence is two things to keep in step.
                figure(MeasurementFormatting.formattedCostPerWear(value, currencyCode: currencyCode))
            case .noPricesOnFile:
                state(String(localized: "No prices on file", comment: "Average cost per wear is undefined because no garment has a purchase price"))
            case .notYetWorn:
                state(String(localized: "Nothing worn yet", comment: "Average cost per wear is undefined because nothing has been worn"))
            case .mixedCurrencies:
                state(String(localized: "Prices in more than one currency", comment: "Average cost per wear is undefined because prices span several currencies"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Says which garments the figure is actually an average over, because
    /// it is not all of them — see `ClosetMetrics.AverageCostPerWear` for
    /// why unpriced garments are left out of both halves of the ratio.
    private var averageCostPerWearDetails: [String] {
        switch metrics.averageCostPerWear {
        case .amount:
            return [
                String(
                    localized: "Total spend across the ^[\(metrics.estimatedValue.pricedItemCount) piece](inflect: true) with a price, over every wear those have.",
                    comment: "Explains which garments the average cost per wear covers"
                )
            ]
        case .noPricesOnFile:
            return [String(localized: "Add what you paid for a piece and this starts counting.", comment: "Average cost per wear: how to make the figure exist")]
        case .notYetWorn:
            return [String(localized: "Mark a piece worn and this fills in.", comment: "Average cost per wear: how to make the figure exist")]
        case .mixedCurrencies(let codes):
            return [
                String(
                    localized: "Your prices are in \(codes.formatted(.list(type: .and))). One average across currencies would not mean anything, so there is not one.",
                    comment: "Explains why there is no single average cost per wear when prices span several currencies"
                )
            ]
        }
    }
}

// MARK: - Most worn and least worn

extension ClosetMetricsRow {

    private var mostWornTile: some View {
        wearExtremeTile(
            label: String(localized: "Most worn", comment: "Closet metrics label: the garment with the highest wear count"),
            extreme: metrics.mostWorn,
            emptyHistoryDetail: String(localized: "Mark a piece worn and this fills in.", comment: "Most worn: how to make the figure exist")
        )
    }

    private var leastWornTile: some View {
        wearExtremeTile(
            label: String(localized: "Least worn", comment: "Closet metrics label: the garment with the lowest wear count"),
            extreme: metrics.leastWorn,
            emptyHistoryDetail: String(localized: "Mark a piece worn and this fills in.", comment: "Least worn: how to make the figure exist")
        )
    }

    /// Tappable only when the metric names one garment.
    ///
    /// A tie names several and an empty state names none, so in those cases
    /// the tile is drawn as text rather than as a control that would either
    /// do nothing or pick one of the tied garments arbitrarily — spec §22's
    /// dead-button rule, and the same reason `WearExtreme.selectableItemID`
    /// exists at all.
    @ViewBuilder
    private func wearExtremeTile(label: String, extreme: ClosetMetrics.WearExtreme, emptyHistoryDetail: String) -> some View {
        let tile = metricTile(
            label: label,
            details: wearExtremeDetails(extreme, emptyHistoryDetail: emptyHistoryDetail)
        ) {
            wearExtremeValue(extreme)
        }

        if let itemID = extreme.selectableItemID {
            Button {
                onSelectItem(itemID)
            } label: {
                tile.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text(String(localized: "Opens this piece", comment: "VoiceOver hint for a closet metric that routes to a garment")))
        } else {
            tile.accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func wearExtremeValue(_ extreme: ClosetMetrics.WearExtreme) -> some View {
        switch extreme {
        case .item(_, let name, _):
            // The garment's own name is the figure here. It is the answer
            // to "which piece", and the count belongs underneath it.
            figure(name)
        case .tie(let itemCount, let wearCount):
            state(tieHeadline(itemCount: itemCount, wearCount: wearCount))
        case .noWearHistory:
            state(String(localized: "Nothing worn yet", comment: "No garment in the closet has ever been worn"))
        case .closetIsEmpty:
            state(String(localized: "Nothing in the closet yet", comment: "The closet holds no garments"))
        }
    }

    /// A tie at zero wears is not "tied" in any useful sense — it is the
    /// pile he has never reached for, which is the reading worth having.
    private func tieHeadline(itemCount: Int, wearCount: Int) -> String {
        guard wearCount > 0 else {
            return String(localized: "^[\(itemCount) piece](inflect: true) not worn yet", comment: "Several garments share the lowest wear count, which is zero")
        }
        return String(localized: "^[\(itemCount) piece](inflect: true) tied", comment: "Several garments share the same wear count")
    }

    private func wearExtremeDetails(_ extreme: ClosetMetrics.WearExtreme, emptyHistoryDetail: String) -> [String] {
        switch extreme {
        case .item(_, _, let wearCount):
            return [String(localized: "^[\(wearCount) wear](inflect: true)", comment: "How many times a garment has been worn")]
        case .tie(_, let wearCount) where wearCount > 0:
            return [
                String(
                    localized: "^[\(wearCount) wear](inflect: true) each, so no single piece leads.",
                    comment: "Several garments share the same wear count and none can be singled out"
                )
            ]
        case .tie:
            // The headline already says "not worn yet". A second line
            // restating it in other words would read as a rendering fault.
            return []
        case .noWearHistory:
            return [emptyHistoryDetail]
        case .closetIsEmpty:
            return []
        }
    }
}

// MARK: - Previews

/// Closets built to land on the states that are easy to get wrong, rather
/// than only on the one where every field happens to be filled in.
private enum ClosetMetricsPreviewData {

    static func item(
        name: String,
        price: Decimal? = nil,
        currency: String? = nil,
        wearCount: Int = 0,
        daysSinceWorn: Int? = nil
    ) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: SampleData.userID,
            name: name,
            category: .top,
            pricePaid: price,
            currency: currency,
            wearCount: wearCount,
            lastWornAt: daysSinceWorn.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }
        )
    }

    /// Three priced garments in a closet of eight — the case where a bare
    /// sum would report an eighth of a wardrobe as the whole of it.
    static let mostlyUnpriced: [ClosetItem] = [
        item(name: "Chore coat", price: 248, currency: "USD", wearCount: 14, daysSinceWorn: 6),
        item(name: "Merino crewneck", price: 50, currency: "USD", wearCount: 30, daysSinceWorn: 1),
        item(name: "Oxford shirt", price: 78, currency: "USD", wearCount: 22, daysSinceWorn: 3)
    ] + (1...5).map { item(name: "Unpriced piece \($0)", wearCount: $0) }

    /// A wardrobe bought across two countries.
    static let mixedCurrency: [ClosetItem] = [
        item(name: "Stockholm parka", price: 4200, currency: "SEK", wearCount: 9, daysSinceWorn: 2),
        item(name: "Suede loafers", price: 320, currency: "USD", wearCount: 9, daysSinceWorn: 2),
        item(name: "Linen shirt", price: 890, currency: "sek ", wearCount: 4, daysSinceWorn: 40)
    ]

    /// Everything typed in, nothing worn yet — the first week of use.
    static let nothingWornYet: [ClosetItem] = [
        item(name: "Navy blazer", price: 480, currency: "USD"),
        item(name: "Grey flannel trousers", price: 190, currency: "USD"),
        item(name: "White sneakers")
    ]
}

#Preview("Full closet") {
    ClosetMetricsRow(metrics: .compute(for: SampleData.closetItems), onSelectItem: { _ in })
        .padding(AstraSpacing.pagePadding)
        .background(AstraColor.backgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Mostly unpriced") {
    ClosetMetricsRow(metrics: .compute(for: ClosetMetricsPreviewData.mostlyUnpriced), onSelectItem: { _ in })
        .padding(AstraSpacing.pagePadding)
        .background(AstraColor.backgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Mixed currencies") {
    ClosetMetricsRow(metrics: .compute(for: ClosetMetricsPreviewData.mixedCurrency), onSelectItem: { _ in })
        .padding(AstraSpacing.pagePadding)
        .background(AstraColor.backgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Nothing worn yet") {
    ClosetMetricsRow(metrics: .compute(for: ClosetMetricsPreviewData.nothingWornYet), onSelectItem: { _ in })
        .padding(AstraSpacing.pagePadding)
        .background(AstraColor.backgroundPrimary)
        .preferredColorScheme(.light)
}

/// `.accessibility3` is the size named "accessibility extra extra extra
/// large" in the system's own vocabulary, and it is the first one this row
/// has to survive with a currency figure and a wrapped coverage sentence in
/// the same cell. `.accessibility4` and `.accessibility5` take the same
/// single-column path, so they differ only in how far each string wraps.
#Preview("Accessibility XXXL") {
    ScrollView {
        ClosetMetricsRow(metrics: .compute(for: ClosetMetricsPreviewData.mostlyUnpriced), onSelectItem: { _ in })
            .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}

#Preview("Accessibility 5, mixed currencies") {
    ScrollView {
        ClosetMetricsRow(metrics: .compute(for: ClosetMetricsPreviewData.mixedCurrency), onSelectItem: { _ in })
            .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
    .environment(\.dynamicTypeSize, .accessibility5)
    .preferredColorScheme(.dark)
}
