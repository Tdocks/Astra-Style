//
//  ClosetColorSwatchRow.swift
//  AstraStyle
//
//  The "Color and secondary colors" field of spec §6.15.
//
//  `closet_items.primary_color` and `.secondary_colors` are free text —
//  words a vision model or the user wrote, not an enum — so this row goes
//  through `AstraGarmentColor.swatches(for:)` rather than guessing at a
//  colour itself, for the reason that file's header gives: a swatch
//  invented at the call site drifts the moment a second screen shows the
//  same word.
//
//  A NAME WITH NO SWATCH RENDERS AS THE NAME ALONE. `AstraSwatch.hex` is
//  `nil` when this build has never heard of the word, and that is the
//  honest answer — painting a rectangle we made up and labelling it with
//  the user's own colour word would be the app telling him what colour his
//  jacket is. The word is shown either way, which is also what spec §19
//  requires: colour is never the sole carrier of meaning.
//
//  EVERY SWATCH IS STROKED. `AstraGarmentColor`'s own doc comment puts
//  this obligation on the view: these are pictures of cloth, not UI
//  surfaces, so they do not flip between appearances — and "bone" or
//  "bright white" on the light-mode background is an invisible chip
//  without a `divider` edge around it.
//

import SwiftUI

/// A field row whose value is a list of colour words, each with its swatch
/// where one is known.
struct ClosetColorSwatchRow: View {
    let label: String
    let colorNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(label)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                // Indexed rather than keyed on `AstraSwatch.id` (the name):
                // "navy" appearing as both primary and secondary colour is
                // a legitimate row, and identical ids in a `ForEach` drop
                // one of them silently.
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, swatch in
                    ClosetColorSwatchChip(swatch: swatch)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One stop, reading "Colour, Navy, Bone" — without this the swatch
        // shapes and their labels are separate elements and VoiceOver
        // walks the palette one chip at a time.
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(colorNames.joined(separator: ", ")))
    }

    private var swatches: [AstraSwatch] {
        AstraGarmentColor.swatches(for: colorNames)
    }
}

/// One colour word, with its swatch when this build knows one.
private struct ClosetColorSwatchChip: View {
    // Scales with Dynamic Type so the swatch keeps its proportion to the
    // word beside it. `AstraSpacing.md` (16 pt) rather than a literal:
    // there is no swatch-diameter token, and riding the 4 pt scale is
    // closer to the design system than inventing a number here would be.
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = AstraSpacing.md

    let swatch: AstraSwatch

    var body: some View {
        HStack(spacing: AstraSpacing.xxs) {
            if let color = swatch.color {
                Circle()
                    .fill(color)
                    .overlay(Circle().strokeBorder(AstraColor.divider, lineWidth: 1))
                    .frame(width: diameter, height: diameter)
                    .accessibilityHidden(true)
            }

            Text(swatch.name)
                .astraText(.body)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
