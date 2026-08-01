//
//  ClosetColorPicker.swift
//  AstraStyle
//
//  The colour half of the closet add/edit form (ticket P3-CLOSET-08).
//
//  THE PROBLEM THIS FILE EXISTS TO SOLVE. `ClosetItem.primaryColor` is a
//  free-text `String?` and `closet_items.primary_color` is a nullable text
//  column, so anything is storable. `AstraGarmentColor` knows about seventy
//  words. Those two facts pull in opposite directions:
//
//  * A plain text field produces "navy blue-ish" and "sort of green", which
//    no swatch resolves, which the §10 wardrobe graph cannot group, and
//    which the item detail screen then renders as a word with a blank space
//    beside it where every other item has a colour.
//  * A closed picker over the known words loses every garment the table has
//    never heard of. The server's own palette vocabulary is content and is
//    expected to grow (see `AstraGarmentColor`'s header), so a closed list
//    would be this build's guess at a set that is not ours to close.
//
//  So: SUGGESTIONS, NOT A PICKER. A normal text field the man can type
//  anything into, with a row of the words this build definitely understands
//  sitting under it. Tapping one fills the field; typing "oat" filters the
//  row down to "Oatmeal". The common case becomes one tap and resolves to a
//  swatch; the uncommon case is never blocked.
//
//  AND NO GUESSED RECTANGLES. `AstraGarmentColor.swatch(for:)` returns
//  `hex == nil` for a word it does not know, and this file renders NOTHING
//  in that case rather than a plausible-looking square. Showing the user a
//  colour the app invented, next to the word he typed, is worse than
//  showing him no colour at all — it is the app asserting something untrue
//  about his own jacket. Every swatch that IS drawn is stroked with
//  `AstraColor.divider`, because a bone or bright-white swatch has no edge
//  of its own against a light background.
//

import SwiftUI

// MARK: - The swatch

/// A single colour swatch, or nothing at all.
///
/// `EmptyView` — not a grey placeholder — when the word is unknown. A
/// placeholder is a rectangle the user reads as "this garment is grey".
struct ClosetColorSwatch: View {
    let name: String
    var size: CGFloat = AstraSpacing.md

    var body: some View {
        if let color = AstraGarmentColor.swatch(for: name).color {
            RoundedRectangle(cornerRadius: AstraSpacing.xxs, style: .continuous)
                .fill(color)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: AstraSpacing.xxs, style: .continuous)
                        .strokeBorder(AstraColor.divider, lineWidth: 1)
                )
                // The word is always shown next to it by every caller, and
                // spec §19 forbids colour as the sole carrier of meaning —
                // so the swatch itself is decoration and announcing it
                // would just repeat the label.
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Live reading of what was typed

/// One line under a colour field confirming what the app made of the word.
///
/// Present because the alternative is silence: a man types "burnt sienna",
/// no swatch appears, and nothing tells him whether that is because the
/// word is wrong, because the field did not register, or because this build
/// simply has no swatch for it. The third is the truth and it is worth a
/// sentence — his word is still saved either way, which is the part that
/// actually matters and the part he cannot otherwise know.
struct ClosetColorReading: View {
    let name: String

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let swatch = AstraGarmentColor.swatch(for: trimmed)
            HStack(spacing: AstraSpacing.xs) {
                ClosetColorSwatch(name: trimmed)
                Text(swatch.hex == nil ? unknownNote : trimmed)
                    .astraText(.caption)
                    .foregroundStyle(swatch.hex == nil ? AstraColor.textMuted : AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private var unknownNote: String {
        String(localized: "Saved as you wrote it. There's no swatch for that word yet.",
               comment: "Shown when a typed garment colour has no matching swatch")
    }
}

// MARK: - Suggestions

/// The chip cloud of colour words this build resolves to a swatch.
///
/// A cloud rather than a horizontal scroller, for the reason
/// `AstraWrappingHStack` was written: a sideways scroller hides its last
/// options behind a gesture with no affordance, and does it worst at the
/// largest text sizes.
struct ClosetColorSuggestions: View {
    /// Filters the list. Pass what the user has typed so far; pass `""` to
    /// show the opening set.
    let query: String
    let isSelected: (String) -> Bool
    let select: (String) -> Void
    /// A group label so VoiceOver announces what these chips choose
    /// between rather than reading twenty-four loose colour names.
    let groupLabel: String

    var body: some View {
        let matches = ClosetColorVocabulary.matches(for: query)
        if !matches.isEmpty {
            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                ForEach(matches, id: \.self) { word in
                    AstraChip(word, isSelected: isSelected(word)) {
                        select(word)
                        AstraHaptics.selection()
                    }
                    .accessibilityIdentifier("closet.form.colorSuggestion.\(word.lowercased())")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(groupLabel))
        }
    }
}

// MARK: - Chosen secondary colours

/// The colours already added to `secondaryColors`, each with its swatch and
/// its own remove control.
///
/// Removal is a button on the chip rather than a swipe or a long press:
/// this is a list that is usually two items long, and a gesture nobody can
/// see is how a mistyped colour stays on a garment forever.
struct ClosetColorTokenList: View {
    let colors: [String]
    let remove: (String) -> Void

    var body: some View {
        if !colors.isEmpty {
            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                ForEach(colors, id: \.self) { color in
                    Button {
                        remove(color)
                        AstraHaptics.warning()
                    } label: {
                        HStack(spacing: AstraSpacing.xxs) {
                            ClosetColorSwatch(name: color, size: AstraSpacing.sm)
                            Text(color)
                                .astraText(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "xmark")
                                .imageScale(.small)
                        }
                        .foregroundStyle(AstraColor.textSecondary)
                        .padding(.horizontal, AstraSpacing.md)
                        .padding(.vertical, AstraSpacing.xs)
                        .frame(minHeight: AstraSize.minTapTarget)
                        .background(Capsule(style: .continuous).fill(AstraColor.backgroundSecondary))
                        .overlay(Capsule(style: .continuous).strokeBorder(AstraColor.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(String(
                        format: String(localized: "Remove %@", comment: "Remove a chosen colour; %@ is the colour name"),
                        color
                    )))
                    .accessibilityIdentifier("closet.form.secondaryColor.\(color.lowercased())")
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: - Vocabulary

/// The colour words offered as suggestions.
///
/// A HAND-PICKED SUBSET, not the whole table, and not a list this file
/// derives from `AstraGarmentColor` — that type keeps its table private on
/// purpose and it holds words that are not garment colours at all ("neon
/// brights", "pale pastels" are Style DNA palette categories). What is here
/// is the vocabulary a man's wardrobe is actually described in, ordered by
/// how often it comes up rather than alphabetically, so the first row is
/// navy, black and charcoal rather than beige, black and blue.
///
/// Every entry was checked against `AstraGarmentColor.swatch(for:)` at the
/// time of writing. If the table ever drops one, the chip still works —
/// it just stops drawing a swatch, which is the same honest degradation
/// every other unknown word gets.
enum ClosetColorVocabulary {
    static let all: [String] = [
        "Navy", "Black", "Charcoal", "Grey", "White", "Cream", "Bone", "Oatmeal",
        "Sand", "Camel", "Tan", "Brown", "Khaki", "Olive", "Green", "Forest green",
        "Blue", "Sky blue", "Indigo", "Burgundy", "Oxblood", "Rust", "Terracotta",
        "Red", "Mustard", "Yellow", "Plum", "Stone", "Sage", "Ivory"
    ]

    /// How many chips are shown before the user narrows things down.
    ///
    /// Thirty chips is a wall the eye slides off; twelve is a row and a
    /// half he can read. Typing anything at all lifts the cap, because at
    /// that point the list is a search result and truncating a search
    /// result is how a match goes missing.
    static let openingCount = 12

    static func matches(for query: String) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return Array(all.prefix(openingCount)) }
        // Contains rather than has-prefix: "green" should still find
        // "Forest green", which is the case a prefix match gets wrong.
        return all.filter { $0.lowercased().contains(needle) }
    }
}
