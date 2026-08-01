//
//  ClosetCategoryTile.swift
//  AstraStyle
//
//  One tile in the Closet overview's category grid (spec §6.14 "Category
//  tiles": Tops, Bottoms, Outerwear, Shoes, Accessories, Watches,
//  Fragrance, All items).
//
//  NO GLYPHS, DELIBERATELY. The obvious design gives each category an SF
//  Symbol, and SF Symbols has no honest set for this: there is a `tshirt`
//  and there is a `shoe`, but there is nothing for trousers, and a
//  wardrobe screen where three of eight tiles wear a coat hanger because
//  the glyph does not exist is worse than one where none of them does. A
//  missing symbol name is also silent — it renders as nothing at runtime
//  and compiles perfectly. So the tile is typographic: the count in the
//  editorial serif, the category name beneath it. That is the information
//  the tile exists to carry, and it survives Dynamic Type, localisation
//  and a wardrobe of zero.
//

import SwiftUI

struct ClosetCategoryTile: View {
    let title: String
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(count.formatted())
                    .astraText(.title1)
                    // A count is a numeral, not a label, so gold here is a
                    // TEXT use and takes the accessible variant (spec §3 /
                    // docs/07).
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(title)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: AstraSize.minTapTarget, alignment: .topLeading)
            .padding(AstraSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .fill(AstraColor.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .strokeBorder(AstraColor.divider, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        // Read as one thing, not as a numeral followed by a word.
        //
        // The count is the accessibility VALUE rather than part of the
        // label, which is both the platform convention and the way to
        // avoid inventing a plural: "Outerwear, 1" and "Outerwear, 6" are
        // each correct, where any hand-written "1 pieces" is not, and a
        // count noun that reads correctly in English is not a count noun
        // that reads correctly in every language a String Catalog will
        // eventually carry.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(count.formatted()))
        .accessibilityHint(Text(String(localized: "Opens this part of your closet", comment: "VoiceOver hint on a closet category tile")))
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Category tiles") {
    LazyVGrid(columns: ClosetGridMetrics.columns(for: .large), spacing: AstraSpacing.md) {
        ClosetCategoryTile(title: "Tops", count: 12, action: {})
        ClosetCategoryTile(title: "Outerwear", count: 0, action: {})
        ClosetCategoryTile(title: "Accessories", count: 3, action: {})
        ClosetCategoryTile(title: "All items", count: 25, action: {})
    }
    .padding(AstraSpacing.pagePadding)
    .background(AstraColor.backgroundPrimary)
    .preferredColorScheme(.dark)
}
