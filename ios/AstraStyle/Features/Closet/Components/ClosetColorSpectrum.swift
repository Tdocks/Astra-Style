//
//  ClosetColorSpectrum.swift
//  AstraStyle
//
//  Spec §6.14's third view: "Color spectrum".
//
//  Takes the same four parameters as `ClosetItemGrid`, in the same order,
//  so the three view modes are interchangeable at the call site. This is
//  the one of the three that does not render its input in the order it
//  was handed — the caller passes the closet in its normal order and this
//  view re-orders it through `ClosetColorSpectrumOrder`, because that
//  re-ordering is the entire mode.
//
//  WHY THIS REUSES `ClosetGridTile` RATHER THAN DRAWING ITS OWN TILE.
//  A colour spectrum is not a different way of drawing a garment; it is a
//  different way of arranging the same garments. The tile, the column
//  rule and the 4:5 crop all come from the editorial grid unchanged, and
//  what this view adds is the order and the group boundaries. A second
//  tile here would be a second thing to keep in step with
//  `ClosetGridTile` for no gain — and `ClosetGridMetrics`'s own header
//  already records why the column rule is stated once rather than per
//  screen. It also keeps the mode switch honest: the same garments, in a
//  different order, rather than a different screen wearing the same data.
//
//  GROUP BOUNDARIES: LEGIBLE, NOT LOUD.
//  Each group carries a `micro` eyebrow, a count, a hairline rule, and —
//  where the group needs it — one line saying why it sits where it does.
//  The six hue bands carry no explanation, because a header reading
//  "Blues" over a screenful of blue explains itself and a sentence under
//  every group is noise. The neutrals and the two unplaced groups do
//  carry one: a man looking at a colour spectrum is entitled to know why
//  his greys are not in it and why five garments are sitting past the end
//  of the colours. A silent tail reads as a sorting fault.
//
//  THE SWATCH RUN BESIDE EACH HEADER IS REAL COLOUR, NEVER A STAND-IN.
//  It is drawn from the swatches actually resolved for the garments in
//  that group, in their own dark-to-light order, deduplicated. A single
//  invented "blue" standing for the Blues group would be the app painting
//  a rectangle it made up, which `AstraGarmentColor`'s header rules out —
//  and it would be a worse summary than the truth, which is the six blues
//  the closet actually holds. Every chip is stroked with
//  `AstraColor.divider` so a bone or bright-white one still has an edge
//  in light mode, and every chip is decorative: the group's name carries
//  the meaning for VoiceOver (spec §19).
//

import SwiftUI

/// The closet regrouped and reordered by colour (spec §6.14 "Color
/// spectrum"). Ordering lives in `ClosetColorSpectrumOrder`.
struct ClosetColorSpectrum: View {
    private let items: [ClosetItem]
    private let imageURL: (ClosetItem) -> URL?
    private let onTileVisible: (ClosetItem) -> Void
    private let onTileTap: (ClosetItem) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        items: [ClosetItem],
        imageURL: @escaping (ClosetItem) -> URL?,
        onTileVisible: @escaping (ClosetItem) -> Void,
        onTileTap: @escaping (ClosetItem) -> Void
    ) {
        self.items = items
        self.imageURL = imageURL
        self.onTileVisible = onTileVisible
        self.onTileTap = onTileTap
    }

    var body: some View {
        // `LazyVGrid` for spec §20's 60 fps target: a tile that has not
        // been built has not asked for its photograph, and `onTileVisible`
        // is what `ClosetViewModel` coalesces a screenful of lookups from.
        // Sections rather than one flat grid so a group boundary is a
        // structural fact rather than a gap the reader has to infer.
        LazyVGrid(
            columns: ClosetGridMetrics.columns(for: dynamicTypeSize),
            alignment: .leading,
            spacing: AstraSpacing.lg
        ) {
            ForEach(segments) { segment in
                Section {
                    ForEach(segment.items) { item in
                        ClosetGridTile(
                            item: item,
                            imageURL: imageURL(item),
                            onVisible: { onTileVisible(item) },
                            onTap: { onTileTap(item) }
                        )
                    }
                } header: {
                    ClosetColorSpectrumHeader(segment: segment)
                }
            }
        }
    }

    /// Computed once per body evaluation rather than inside it, so the
    /// sort is not repeated per section. One pass over the closet: a
    /// swatch lookup and a colour conversion per garment, then one sort.
    private var segments: [ClosetColorSpectrumOrder.Segment] {
        ClosetColorSpectrumOrder.segments(for: items)
    }
}

// MARK: - Group header

/// One group's boundary: what it is, how many pieces are in it, the
/// colours it actually holds, and — where it is needed — why it sits
/// where it does.
private struct ClosetColorSpectrumHeader: View {
    let segment: ClosetColorSpectrumOrder.Segment

    /// Anchored to `caption2`, which is what `micro` scales against, so
    /// the chips keep their proportion to the eyebrow beside them.
    @ScaledMetric(relativeTo: .caption2) private var swatchDiameter: CGFloat = AstraSpacing.sm

    /// Enough to read the group at a glance, not so many that the header
    /// becomes the picture. A group with more distinct colours than this
    /// is already showing them at full size in the tiles underneath.
    private static let maximumSwatches = 5

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: AstraSpacing.xs) {
                Text(segment.band.displayName)
                    .astraText(.micro)
                    .foregroundStyle(AstraColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                swatchRun

                Spacer(minLength: AstraSpacing.xs)

                Text(segment.items.count.formatted())
                    .astraText(.micro)
                    .foregroundStyle(AstraColor.textMuted)
            }

            if let explanation = segment.band.explanation {
                Text(explanation)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // A hairline rather than a heavier rule or a filled bar: the
            // boundary has to be findable while scrolling past it without
            // competing with the garments it separates.
            Rectangle()
                .fill(AstraColor.divider)
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AstraSpacing.sm)
        // One stop per group, reading "Blues, 6 pieces" — without this
        // VoiceOver walks the eyebrow, each chip, the count and the
        // explanation as separate elements before reaching a garment.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isHeader)
    }

    /// The colours this group actually holds, in the order the garments
    /// below are in. Decorative — the group's name carries the meaning —
    /// so the whole run is hidden from VoiceOver (spec §19).
    private var swatchRun: some View {
        HStack(spacing: AstraSpacing.xxs) {
            ForEach(segment.swatchHexes.prefix(Self.maximumSwatches), id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    // Every swatch is stroked, per `AstraGarmentColor`'s
                    // header: a bone or bright-white chip has no edge of
                    // its own on the light background.
                    .overlay(Circle().strokeBorder(AstraColor.divider, lineWidth: 1))
                    .frame(width: swatchDiameter, height: swatchDiameter)
            }
        }
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        let heading = String(
            localized: "\(segment.band.displayName), ^[\(segment.items.count) piece](inflect: true)",
            comment: "VoiceOver label for a closet colour spectrum group: the group's name, then how many garments are in it"
        )
        guard let explanation = segment.band.explanation else { return heading }
        return "\(heading). \(explanation)"
    }
}

// MARK: - Previews

/// A closet built to exercise every group at once — one run round the
/// wheel, a neutral ramp, a colour word this build has no swatch for, and
/// a garment with no colour on file. Deliberately shuffled relative to
/// the order it should come out in, so a preview that renders it in
/// declaration order is visibly wrong rather than accidentally right.
private enum ClosetColorSpectrumPreviewData {

    static func item(_ name: String, _ color: String?) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: SampleData.userID,
            name: name,
            category: .top,
            primaryColor: color
        )
    }

    static let everyGroup: [ClosetItem] = [
        item("Grey hoodie", nil),
        item("Sky Blue Oxford", "sky blue"),
        item("Bone Linen Shirt", "bone"),
        item("Barn Red Overshirt", "barn red"),
        item("Plum Knit", "plum"),
        item("Camp Collar Shirt", "burnt sienna"),
        item("Navy Merino Crewneck", "navy"),
        item("Charcoal Flannel", "charcoal"),
        item("Mustard Cardigan", "mustard"),
        item("Olive Chore Coat", "olive"),
        item("Camel Overcoat", "camel"),
        item("Black Tie Shirt", "black"),
        item("Forest Green Fleece", "forest green"),
        item("Rust Corduroy Shirt", "rust"),
        item("Ink Blue Blazer", "ink blue"),
        item("Burgundy Lambswool", "burgundy"),
        item("Bright White Tee", "bright white"),
        item("Field Jacket", nil)
    ]
}

#Preview("Colour spectrum") {
    ScrollView {
        ClosetColorSpectrum(
            items: ClosetColorSpectrumPreviewData.everyGroup,
            imageURL: { _ in nil },
            onTileVisible: { _ in },
            onTileTap: { _ in }
        )
        .padding(.horizontal, AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
    .preferredColorScheme(.dark)
}

/// Light mode is where the swatch strokes earn their place — a bone or
/// bright-white chip on the `#F8F5EF` background has no edge without one.
#Preview("Colour spectrum — light") {
    ScrollView {
        ClosetColorSpectrum(
            items: ClosetColorSpectrumPreviewData.everyGroup,
            imageURL: { _ in nil },
            onTileVisible: { _ in },
            onTileTap: { _ in }
        )
        .padding(.horizontal, AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
    .preferredColorScheme(.light)
}

/// The sample closet, which is mostly neutral — the case that decided the
/// group order. Leading with the neutrals would open this mode on a
/// screenful of grey.
#Preview("Colour spectrum — sample closet") {
    ScrollView {
        ClosetColorSpectrum(
            items: SampleData.closetItems,
            imageURL: { _ in nil },
            onTileVisible: { _ in },
            onTileTap: { _ in }
        )
        .padding(.horizontal, AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Colour spectrum — accessibility 5") {
    ScrollView {
        ClosetColorSpectrum(
            items: ClosetColorSpectrumPreviewData.everyGroup,
            imageURL: { _ in nil },
            onTileVisible: { _ in },
            onTileTap: { _ in }
        )
        .padding(.horizontal, AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
    .environment(\.dynamicTypeSize, .accessibility5)
    .preferredColorScheme(.dark)
}
