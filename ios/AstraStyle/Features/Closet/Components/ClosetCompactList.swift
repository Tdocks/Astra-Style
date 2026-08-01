//
//  ClosetCompactList.swift
//  AstraStyle
//
//  Spec §6.14's second view: "Compact list".
//
//  Takes the same four parameters as `ClosetItemGrid`, in the same order,
//  so the two are interchangeable at the call site and the screen chooses
//  between them without knowing anything about either.
//
//  WHAT THIS MODE IS FOR, AND WHAT THAT DECIDES ABOUT EVERY ROW.
//  The editorial grid is for looking at a wardrobe; this is for finding
//  one garment in a large one. That is the whole difference, and it fixes
//  three things. The photograph shrinks to a 56 px thumbnail — the
//  `ImageDownsampling.ThumbnailSize.listRowThumbnail` case exists for
//  exactly this surface — because at scanning speed the picture is a
//  landmark rather than the subject. More lines fit per row than the grid
//  can carry under a tile. And the lines chosen are the ones that tell
//  two similar garments apart: what he calls it, who made it, what kind
//  of thing it is, and what colour it is.
//
//  IT IS NOT A SECOND ITEM DETAIL SCREEN, AND THE OMISSIONS ARE THE
//  ARGUMENT. Price, cost per wear, wear count, purchase date, material,
//  season and size are all on the garment and all deliberately absent
//  here. None of them helps a man pick the right navy jumper out of four;
//  they answer questions he asks after he has found it, which is what
//  §6.15's detail screen is for. The one non-identifying line that does
//  earn its place is the garment's state, and only when it is not the
//  default — "In the wash" is the difference between a shirt he can wear
//  today and one he cannot, and it is the reason a row he expected to
//  find is not the row he wants.
//
//  EVERY SWATCH IS STROKED. `AstraGarmentColor`'s header puts that
//  obligation on the view: swatches are pictures of cloth rather than UI
//  surfaces, so they do not flip between appearances, and "bone" on the
//  light background is an invisible chip without a `divider` edge. A
//  colour word this build has no swatch for renders as the word alone —
//  never a rectangle Astra invented and labelled with the user's colour.
//

import SwiftUI

/// The closet as one garment per row (spec §6.14 "Compact list").
struct ClosetCompactList: View {
    private let items: [ClosetItem]
    private let imageURL: (ClosetItem) -> URL?
    private let onRowVisible: (ClosetItem) -> Void
    private let onRowTap: (ClosetItem) -> Void

    init(
        items: [ClosetItem],
        imageURL: @escaping (ClosetItem) -> URL?,
        onRowVisible: @escaping (ClosetItem) -> Void,
        onRowTap: @escaping (ClosetItem) -> Void
    ) {
        self.items = items
        self.imageURL = imageURL
        self.onRowVisible = onRowVisible
        self.onRowTap = onRowTap
    }

    var body: some View {
        // Lazy for the same reason the grid is: spec §20 asks a closet of
        // this size to scroll at 60 fps, and a row that has not been built
        // has not asked for its photograph either — `onRowVisible` is the
        // signal `ClosetViewModel` coalesces a screenful of lookups from.
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                // A rule between rows rather than under them, so the list
                // never ends on a line hanging under the last garment.
                if index > 0 {
                    Rectangle()
                        .fill(AstraColor.divider)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }

                ClosetCompactListRow(
                    item: item,
                    imageURL: imageURL(item),
                    onVisible: { onRowVisible(item) },
                    onTap: { onRowTap(item) }
                )
            }
        }
    }
}

// MARK: - Row

/// One garment, at scanning density.
private struct ClosetCompactListRow: View {
    let item: ClosetItem
    let imageURL: URL?
    /// Called each time the row comes on screen, exactly as
    /// `ClosetGridTile.onVisible` is — the view model turns a screenful of
    /// these into one signing request.
    let onVisible: () -> Void
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Scales with Dynamic Type so the chip keeps its proportion to the
    /// word beside it, anchored to `caption` because that is the line it
    /// sits on. `AstraSpacing.sm` rather than a literal: there is no
    /// swatch-diameter token, and riding the 4 pt scale is closer to the
    /// design system than inventing a number here — the same call
    /// `ClosetColorSwatchRow` already made.
    @ScaledMetric(relativeTo: .caption) private var swatchDiameter: CGFloat = AstraSpacing.sm

    var body: some View {
        Button(action: onTap) {
            layout
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AstraSpacing.sm)
                .frame(minHeight: AstraSize.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // One element per garment. Without this VoiceOver reads the
        // photograph, the name, the identifying line and the state as four
        // separate stops, and a closet of forty pieces becomes a hundred
        // and sixty swipes.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text(String(localized: "Opens this piece", comment: "VoiceOver hint on a closet list row")))
        .accessibilityAddTraits(.isButton)
        .onAppear(perform: onVisible)
    }

    /// The thumbnail moves above the text at accessibility sizes rather
    /// than staying beside it. Holding the 56 pt column at AX5 leaves the
    /// three lines wrapping in what is left of the width, which is where a
    /// garment name starts breaking one word to a line. Same escape
    /// `ClosetItemFieldRow` takes, for the same reason.
    @ViewBuilder
    private var layout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                thumbnail
                details
            }
        } else {
            HStack(alignment: .top, spacing: AstraSpacing.md) {
                thumbnail
                details
            }
        }
    }

    /// Deliberately NOT scaled by Dynamic Type. A photograph does not
    /// become more legible when the text around it grows, and growing it
    /// would take the width back off the lines that do — the same call
    /// `AstraSize.referencePreviewHeight` records.
    private var thumbnail: some View {
        AstraRemoteImage(
            url: imageURL,
            aspectRatio: ClosetGridMetrics.tileAspectRatio,
            thumbnail: .listRowThumbnail,
            // `AstraRadius.card` (18 pt) on a 56 pt thumbnail is very
            // nearly a circle; `small` is the radius that token exists for.
            cornerRadius: AstraRadius.small,
            accessibilityDescription: item.name
        )
        // The drawn width IS the decode width, taken from the same case
        // rather than restated as a literal beside it, so the two cannot
        // drift. It is 14 x the 4 pt base unit, so it stays on the scale.
        .frame(width: ImageDownsampling.ThumbnailSize.listRowThumbnail.maxPixelSize)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(item.name)
                .astraText(.body)
                .foregroundStyle(AstraColor.textPrimary)
                // Two lines, then truncate. A garment name is the row's
                // subject, so it gets more room than a caption; letting it
                // run unbounded would let one badly-named piece push the
                // rest of the closet off the screen.
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !identifiers.isEmpty {
                // Baseline alignment so the chip sits ON the line of type
                // rather than floating in the middle of a wrapped run.
                HStack(alignment: .firstTextBaseline, spacing: AstraSpacing.xxs) {
                    swatch
                    Text(identifiers)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let stateLine {
                Text(stateLine)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Drawn only when this build has a swatch for the word. The word is
    /// shown either way, in `identifiers` — which is also what spec §19
    /// requires: colour is never the sole carrier of meaning. Decorative,
    /// so it is hidden from VoiceOver and the colour travels in the row's
    /// label as text.
    @ViewBuilder
    private var swatch: some View {
        if let colorName, let color = AstraGarmentColor.swatch(for: colorName).color {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(AstraColor.divider, lineWidth: 1))
                .frame(width: swatchDiameter, height: swatchDiameter)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - What a row says

private extension ClosetCompactListRow {

    /// A middot list, which is the dense form this row needs. Punctuation
    /// rather than copy, so it is a constant and not a localised string —
    /// the words it joins are each localised on their own.
    static var identifierSeparator: String { " · " }

    /// The colour word exactly as it is on file, or `nil` when there is
    /// none. Never invented and never normalised for display: this is the
    /// user's own word for his own garment.
    var colorName: String? {
        guard let primaryColor = item.primaryColor?.trimmingCharacters(in: .whitespacesAndNewlines),
              !primaryColor.isEmpty else {
            return nil
        }
        return primaryColor
    }

    /// Who made it, what kind of thing it is, and what colour it is.
    ///
    /// The grid tile shows brand OR subcategory, whichever exists, because
    /// a tile caption has room for one line. A row has room for both, and
    /// the pair is what separates a Sunspel crewneck from a Sunspel polo.
    /// Nothing is invented when a field is absent — the part is simply not
    /// there, and a garment with none of the three gets no second line
    /// rather than an empty one.
    var identifierParts: [String] {
        var parts: [String] = []
        if let brand = item.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
            parts.append(brand)
        }
        if let subcategory = item.subcategory?.trimmingCharacters(in: .whitespacesAndNewlines), !subcategory.isEmpty {
            parts.append(subcategory)
        }
        if let colorName {
            parts.append(colorName)
        }
        return parts
    }

    var identifiers: String {
        identifierParts.joined(separator: Self.identifierSeparator)
    }

    /// The garment's state, and only when it is not the default one.
    ///
    /// Availability is checked first because it is the broader fact — "At
    /// the tailor", "Lent out", "Packed" — and because it subsumes the
    /// laundry case: `AvailabilityState.inLaundry` and
    /// `LaundryState.laundry` deliberately render the same sentence (see
    /// `Enums.swift`), so testing both would say it twice on one row.
    ///
    /// A clean, available garment gets no third line at all. "Clean" and
    /// "Available" on every one of forty rows is forty lines saying
    /// nothing, and it would bury the four rows where the state is the
    /// point.
    var stateLine: String? {
        if item.availabilityState != .available {
            return item.availabilityState.displayName
        }
        if item.laundryState != .clean {
            return item.laundryState.displayName
        }
        return nil
    }

    /// Commas rather than middots: VoiceOver reads a comma as the pause it
    /// is, and a middot as nothing at all.
    var accessibilityLabel: String {
        ([item.name] + identifierParts + [stateLine].compactMap { $0 }).joined(separator: ", ")
    }
}

// MARK: - Previews

/// Closets built to land on the cases a list gets wrong: a garment with
/// nothing but a name, one whose colour this build has no swatch for, and
/// the states that put a third line on a row.
private enum ClosetCompactListPreviewData {

    static func item(
        name: String,
        brand: String? = nil,
        subcategory: String? = nil,
        color: String? = nil,
        laundryState: LaundryState = .clean,
        availabilityState: AvailabilityState = .available
    ) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: SampleData.userID,
            name: name,
            brand: brand,
            category: .top,
            subcategory: subcategory,
            primaryColor: color,
            laundryState: laundryState,
            availabilityState: availabilityState
        )
    }

    static let mixed: [ClosetItem] = [
        item(name: "Merino Crewneck", brand: "Sunspel", subcategory: "Sweater", color: "navy"),
        item(name: "Oxford Button-Down", brand: "J.Crew", subcategory: "Dress Shirt", color: "white", laundryState: .laundry),
        item(name: "Chore Coat", brand: "Todd Snyder", subcategory: "Jacket", color: "olive", availabilityState: .inAlteration),
        // A colour word this build has no swatch for: the word shows, the
        // chip does not.
        item(name: "Camp Collar Shirt", brand: "Drake's", subcategory: "Casual Shirt", color: "burnt sienna"),
        // Nothing but a name, which is what a hurried manual entry gives.
        item(name: "Grey hoodie")
    ]
}

#Preview("Compact list") {
    ScrollView {
        ClosetCompactList(
            items: SampleData.closetItems,
            imageURL: { _ in nil },
            onRowVisible: { _ in },
            onRowTap: { _ in }
        )
        .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Compact list — sparse and stateful rows") {
    ScrollView {
        ClosetCompactList(
            items: ClosetCompactListPreviewData.mixed,
            imageURL: { _ in nil },
            onRowVisible: { _ in },
            onRowTap: { _ in }
        )
        .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
    .preferredColorScheme(.light)
}

#Preview("Compact list — accessibility 5") {
    ScrollView {
        ClosetCompactList(
            items: ClosetCompactListPreviewData.mixed,
            imageURL: { _ in nil },
            onRowVisible: { _ in },
            onRowTap: { _ in }
        )
        .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
    .environment(\.dynamicTypeSize, .accessibility5)
    .preferredColorScheme(.dark)
}
