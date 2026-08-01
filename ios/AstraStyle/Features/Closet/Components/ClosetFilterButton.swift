//
//  ClosetFilterButton.swift
//  AstraStyle
//
//  The filter control spec §6.14 puts in the Closet header, beside search
//  and scan. It opens `ClosetFilterPanelView` and does nothing else.
//
//  IT EXISTS NOW BECAUSE THE PANEL DOES.
//  `ClosetView`'s header records why this control was deliberately absent
//  until this ticket: a filter button in front of an unbuilt panel opens an
//  apology, which is the dead button spec §22 rules out by name. That
//  reasoning is not being overturned, it is being satisfied — the panel is
//  real, so the door to it is real.
//
//  A COUNT, NOT A DOT.
//  The badge states how many of the eight §6.14 facets are narrowing. A
//  plain dot would say only "something is on", which leaves a man who
//  cannot find his navy jacket to open the panel and hunt for what he
//  forgot; a number tells him how much there is to undo before he has
//  opened anything. It counts FACETS rather than values for the reason
//  argued on `ClosetFilters.activeFacetCount`: three categories is one
//  question, not three.
//
//  The count is also what VoiceOver announces, because "Filter" alone is
//  the same announcement whether the closet is untouched or narrowed to
//  four garments — and the badge is the only thing on screen that
//  distinguishes those, which makes it exactly the information a
//  non-visual user is otherwise missing (spec §19).
//
//  ONE PLACE THIS CONTROL SHOULD NOT BE DRAWN. When the closet can offer
//  no filter values at all — an empty closet, or a handful of pieces that
//  differ in nothing — `ClosetFilterOptions.isEmpty` is true and the panel
//  behind this button has nothing but a sentence in it. The panel says so
//  honestly rather than opening blank, but the better answer is not to
//  offer the door: the presenter should draw this only where
//  `!options.isEmpty || activeFacetCount > 0`. The second half of that
//  matters — a filter left on must always remain reachable to turn off.
//

import SwiftUI

/// The Closet header's filter control.
struct ClosetFilterButton: View {

    /// How many §6.14 facets are currently narrowing. `0` draws no badge.
    private let activeFacetCount: Int

    private let action: () -> Void

    init(activeFacetCount: Int, action: @escaping () -> Void) {
        self.activeFacetCount = activeFacetCount
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal.decrease")
                // Matched to the add and scan buttons it sits beside: same
                // glyph size, same weight, same champagne fill. The header
                // has no primary among its three controls and should not
                // grow one here.
                .astraIcon(.emphasis)
                // An icon is a fill, not text (spec §3 / docs/07).
                .foregroundStyle(AstraColor.accentChampagne)
                .frame(minWidth: AstraSize.minTapTarget, minHeight: AstraSize.minTapTarget)
                .overlay(alignment: .topTrailing) {
                    if activeFacetCount > 0 {
                        badge
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .astraAnimation(AstraMotion.standard, value: activeFacetCount)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text(String(
            localized: "Narrows what your closet shows",
            comment: "VoiceOver hint for the closet filter button"
        )))
        .accessibilityIdentifier("closet.header.filters")
    }

    /// The count, in a champagne capsule.
    ///
    /// A numeral rather than colour alone, so the active state survives
    /// both a colour-blind reading and a screenshot in greyscale (spec
    /// §19). `Text(_:format:)` rather than interpolation so the digits are
    /// the ones the user's locale writes.
    private var badge: some View {
        Text(activeFacetCount, format: .number)
            .astraText(.micro)
            // Sitting ON a champagne fill, so the fixed on-accent token.
            .foregroundStyle(AstraColor.textOnAccent)
            .padding(.horizontal, AstraSpacing.xxs)
            .frame(minWidth: AstraSpacing.md, minHeight: AstraSpacing.md)
            .background(Capsule(style: .continuous).fill(AstraColor.accentChampagne))
            // The label already says how many are on; announcing the badge
            // separately would read the number twice.
            .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        switch activeFacetCount {
        case 0:
            return String(localized: "Filters", comment: "VoiceOver label for the closet filter button when nothing is filtered")
        case 1:
            // Spelled out rather than formatted, because a single format
            // string here produces "1 filters on".
            return String(localized: "Filters, 1 on", comment: "VoiceOver label for the closet filter button with one filter active")
        default:
            return String(
                format: String(localized: "Filters, %d on", comment: "VoiceOver label for the closet filter button; %d is how many filters are active"),
                activeFacetCount
            )
        }
    }
}

// MARK: - Previews

#Preview("Nothing filtered") {
    ClosetFilterButton(activeFacetCount: 0) {}
        .padding(AstraSpacing.lg)
        .background(AstraColor.backgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Three facets on") {
    ClosetFilterButton(activeFacetCount: 3) {}
        .padding(AstraSpacing.lg)
        .background(AstraColor.backgroundPrimary)
        .preferredColorScheme(.dark)
}
