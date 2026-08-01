//
//  ClosetItemFieldRow.swift
//  AstraStyle
//
//  The label/value rows the §6.15 item detail screen is mostly made of,
//  plus the two rows that are not plain text (a product link, and the
//  laundry state, which is editable in place).
//
//  WHY ONE ACCESSIBILITY ELEMENT PER ROW. A label and a value in an
//  `HStack` are two accessible children, so VoiceOver stops twice and
//  reads "Brand", then "Sunspel" — the pair is only a pair visually. Every
//  row here collapses to a single element with `accessibilityLabel` for
//  the field name and `accessibilityValue` for its value, which is what
//  makes the rotor read "Brand, Sunspel" in one stop (spec §19).
//
//  WHY THE ROWS RE-STACK AT ACCESSIBILITY TEXT SIZES. A label/value
//  `HStack` at AX5 gives each side roughly half the screen, and a value
//  like "New with tags" truncates while the label beside it has room to
//  spare. Switching to a vertical stack gives the value the full width,
//  which is the difference between a legible screen and a clipped one.
//  Checked here rather than with `ViewThatFits` because both layouts
//  always "fit" — the `HStack` fits by truncating.
//

import SwiftUI

/// A titled group of field rows, drawn on one elevated card.
struct ClosetItemFieldGroup<Content: View>: View {
    private let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: title)
            AstraCard {
                VStack(alignment: .leading, spacing: AstraSpacing.md) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// One `label: value` line — the shape of most of §6.15's field list.
struct ClosetItemFieldRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let label: String
    let value: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    labelText
                    valueText
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: AstraSpacing.md) {
                    labelText
                    Spacer(minLength: AstraSpacing.sm)
                    valueText
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
    }

    private var labelText: some View {
        Text(label)
            .astraText(.callout)
            .foregroundStyle(AstraColor.textSecondary)
            // Wrap rather than truncate. A field name that reads
            // "Purchase da…" is worse than one that takes two lines.
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .astraText(.body)
            .foregroundStyle(AstraColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The product URL row (§6.15 "Product URL").
///
/// Shows the host rather than the full URL: a 180-character affiliate link
/// with tracking parameters is not information, and truncating it to
/// "https://www.mrporter.com/en-gb/mens/prod…" tells the reader less than
/// "mrporter.com" does. The whole row is the tap target so it clears 44 pt
/// on its own without a minimum height forced onto the text.
struct ClosetItemLinkFieldRow: View {
    let label: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(alignment: .firstTextBaseline, spacing: AstraSpacing.md) {
                Text(label)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: AstraSpacing.sm)

                Text(displayHost)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "arrow.up.right")
                    .astraIcon(.disclosure)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(displayHost))
        .accessibilityAddTraits(.isLink)
    }

    /// `host()` is nil for a URL with no authority component (a `mailto:`,
    /// a bare path). Falling back to the whole string is honest — it is
    /// what the user stored — and avoids a row that says nothing.
    private var displayHost: String {
        url.host() ?? url.absoluteString
    }
}

/// The laundry-state row (§6.15 "Laundry state"), editable in place.
///
/// A picker here rather than in the action row, and a one-tap button in
/// the action row rather than a picker: the two are the same column served
/// two ways on purpose. The morning case is one-handed and one-tap — the
/// shirt is coming off and going in the basket — and burying that behind a
/// four-item menu makes the common action the slowest one. The other three
/// states ("Worn once" for the shirt that is going back on the hanger,
/// "Unavailable" for the jacket at the tailor) are corrections, not
/// reflexes, and belong with the field they correct.
struct ClosetItemLaundryFieldRow: View {
    let label: String
    let laundryState: LaundryState
    let isUpdating: Bool
    let onChange: (LaundryState) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AstraSpacing.md) {
            Text(label)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: AstraSpacing.sm)

            if isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }

            Picker(selection: selection) {
                ForEach(LaundryState.allCases) { state in
                    Text(state.displayName).tag(state)
                }
            } label: {
                Text(label)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(AstraColor.accentChampagneAccessible)
            .disabled(isUpdating)
            .frame(minHeight: AstraSize.minTapTarget)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
    }

    /// The picker writes through a closure rather than a stored binding so
    /// the view model stays the only thing that can change the item, and
    /// so the write can be async and roll back.
    private var selection: Binding<LaundryState> {
        Binding(
            get: { laundryState },
            set: { onChange($0) }
        )
    }
}

// MARK: - The three field groups of spec §6.15
//
// Grouped by the question each answers rather than by column order: what
// the garment IS, how it has been WORN, and what it COST. A single
// eighteen-row list is technically the same information and is read by
// nobody.
//
// FREE-TEXT VALUES RENDER EXACTLY AS STORED. `material`, `primary_color`
// and `secondary_colors` are words a vision model or the user wrote.
// Normalising their casing here would be this screen quietly editing the
// user's own words, and `AstraGarmentColor`'s header is explicit that the
// name is displayed as written.

/// What the garment is: spec §6.15's brand, colours, material, pattern,
/// size, fit, condition and seasonality.
///
/// Every row is conditional and the whole group disappears when a freshly
/// scanned item has none of them — an empty card titled "The piece" is
/// worse than no card.
struct ClosetItemPieceSection: View {
    let item: ClosetItem

    var body: some View {
        if hasAnyField {
            ClosetItemFieldGroup(title: String(localized: "The piece", comment: "Item detail section: what the garment is")) {
                if let brand = item.brand, !brand.isEmpty {
                    ClosetItemFieldRow(label: String(localized: "Brand", comment: "Garment field"), value: brand)
                }
                if !colorNames.isEmpty {
                    ClosetColorSwatchRow(
                        label: String(localized: "Colour", comment: "Garment field: primary and secondary colours"),
                        colorNames: colorNames
                    )
                }
                if !item.material.isEmpty {
                    ClosetItemFieldRow(
                        label: String(localized: "Material", comment: "Garment field"),
                        value: item.material.joined(separator: ", ")
                    )
                }
                if let pattern = item.pattern {
                    ClosetItemFieldRow(label: String(localized: "Pattern", comment: "Garment field"), value: pattern.displayName)
                }
                if let size = item.size, !size.isEmpty {
                    ClosetItemFieldRow(label: String(localized: "Size", comment: "Garment field"), value: size)
                }
                if let fit = item.fit {
                    ClosetItemFieldRow(label: String(localized: "Fit", comment: "Garment field: how the garment is cut"), value: fit.displayName)
                }
                if let condition = item.condition {
                    ClosetItemFieldRow(label: String(localized: "Condition", comment: "Garment field"), value: condition.displayName)
                }
                if !item.seasonality.isEmpty {
                    ClosetItemFieldRow(
                        label: String(localized: "Season", comment: "Garment field: which seasons the garment suits"),
                        value: item.seasonality.map(\.displayName).joined(separator: ", ")
                    )
                }
            }
        }
    }

    /// Primary first, then the secondaries, in the order they were stored.
    private var colorNames: [String] {
        var names: [String] = []
        if let primaryColor = item.primaryColor, !primaryColor.isEmpty {
            names.append(primaryColor)
        }
        names.append(contentsOf: item.secondaryColors.filter { !$0.isEmpty })
        return names
    }

    private var hasAnyField: Bool {
        item.brand?.isEmpty == false
            || !colorNames.isEmpty
            || !item.material.isEmpty
            || item.pattern != nil
            || item.size?.isEmpty == false
            || item.fit != nil
            || item.condition != nil
            || !item.seasonality.isEmpty
    }
}

/// How the garment has been worn: spec §6.15's wear count, last worn, cost
/// per wear and laundry state.
///
/// Unlike the other two groups, none of these rows is ever omitted. A blank
/// here is the whole point — "not yet worn" and "add a price" are the two
/// sentences that make a man do something about a garment, and hiding them
/// would hide the screen's only real prompt.
///
/// Outfit count is missing from this group and from this build. It needs
/// `outfit_items`, which is Phase 4; a "0 outfits" row today would be a
/// confident zero for a table that does not exist.
struct ClosetItemWearSection: View {
    let item: ClosetItem
    let isUpdatingLaundryState: Bool
    let onSetLaundryState: (LaundryState) -> Void

    var body: some View {
        ClosetItemFieldGroup(title: String(localized: "Wear", comment: "Item detail section: how much the garment has been worn")) {
            ClosetItemFieldRow(
                label: String(localized: "Worn", comment: "Garment field: number of recorded wears"),
                value: ClosetItemDetailCopy.wearCount(item.wearCount)
            )
            ClosetItemFieldRow(
                label: String(localized: "Last worn", comment: "Garment field"),
                value: ClosetItemDetailCopy.lastWorn(item.lastWornAt)
            )
            ClosetItemFieldRow(
                label: String(localized: "Cost per wear", comment: "Garment field"),
                value: ClosetItemDetailCopy.costPerWear(for: item).text
            )
            ClosetItemLaundryFieldRow(
                label: String(localized: "Laundry", comment: "Garment field: where the garment is in the wash cycle"),
                laundryState: item.laundryState,
                isUpdating: isUpdatingLaundryState,
                onChange: onSetLaundryState
            )
            // Not one of §6.15's listed fields, and shown only when it says
            // something. "Available" is the default for every row in the
            // table, so printing it would add a line that is true of
            // everything; "At the tailor" is the reason a garment is missing
            // from this morning's outfit, which is worth a line.
            if item.availabilityState != .available {
                ClosetItemFieldRow(
                    label: String(localized: "Availability", comment: "Garment field: whether the garment can be worn right now"),
                    value: item.availabilityState.displayName
                )
            }
        }
    }
}

/// What the garment cost: spec §6.15's purchase date, price paid, retailer
/// and product URL. Omitted entirely for a garment with no purchase record,
/// which is most of a closet scanned from a wardrobe rail.
struct ClosetItemPurchaseSection: View {
    let item: ClosetItem

    var body: some View {
        if hasAnyField {
            ClosetItemFieldGroup(title: String(localized: "Purchase", comment: "Item detail section: what the garment cost")) {
                if let purchaseDate = item.purchaseDate {
                    ClosetItemFieldRow(
                        label: String(localized: "Bought", comment: "Garment field: purchase date"),
                        value: ClosetItemDetailCopy.purchaseDate(purchaseDate)
                    )
                }
                if let pricePaid = item.pricePaid {
                    ClosetItemFieldRow(
                        label: String(localized: "Price paid", comment: "Garment field"),
                        value: ClosetItemDetailCopy.currency(pricePaid, code: item.currency ?? ClosetItemDetailCopy.fallbackCurrencyCode)
                    )
                }
                if let retailer = item.retailer, !retailer.isEmpty {
                    ClosetItemFieldRow(label: String(localized: "Retailer", comment: "Garment field"), value: retailer)
                }
                if let productURL = item.productURL {
                    ClosetItemLinkFieldRow(
                        label: String(localized: "Product page", comment: "Garment field: link to the product online"),
                        url: productURL
                    )
                }
            }
        }
    }

    private var hasAnyField: Bool {
        item.purchaseDate != nil
            || item.pricePaid != nil
            || item.retailer?.isEmpty == false
            || item.productURL != nil
    }
}
