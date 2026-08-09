//
//  ClosetViewModeToggle.swift
//  AstraStyle
//
//  The control that switches between spec §6.14's three closet views.
//
//  WHY IT IS A MENU AND NOT THREE CHIPS OR A SEGMENTED CONTROL.
//  The §6.14 header row already carries the screen's display-weight
//  title, an add button and a scan button, and `ClosetView`'s own header
//  comment argues at length about which controls earn a place in it. A
//  filter button is still owed that row. Three chips or a three-way
//  segmented control is a fourth control the width of the other three put
//  together, and at accessibility text sizes "Editorial grid / Compact
//  list / Colour spectrum" is wider than the screen — so it would either
//  truncate the mode names, which is the one thing that cannot happen
//  when the names are what disambiguate the icons, or wrap into a second
//  row that pushes the closet itself further down the page.
//
//  A menu costs one slot, the width of a single glyph, at every text
//  size. It is also what iOS itself uses for exactly this job — the view
//  options menu in Photos and Files — so it needs no learning.
//
//  WHAT THAT COSTS, AND HOW IT IS PAID. The trigger is an icon, and an
//  icon alone is genuinely ambiguous for a colour-spectrum mode: a grid
//  and a list read at a glance, a palette does not say "your closet,
//  reordered by colour". So the icon never carries the meaning on its
//  own. The control's accessibility label is "View" and its value is the
//  current mode's name, so VoiceOver reads "View, Colour spectrum,
//  button" without the user opening anything, and the menu behind it
//  names all three modes in words the moment it is tapped. The ambiguity
//  lasts exactly as long as the user is not looking at the answer.
//
//  WHY A `Picker` INSIDE THE MENU RATHER THAN THREE `Button`s.
//  A picker is what makes the selected row announce itself as selected
//  and draw the system checkmark, without this file hand-rolling either.
//  Hand-rolled menu rows can carry a checkmark glyph, but the `isSelected`
//  accessibility trait on a menu item is not reliably honoured, and
//  "which one am I on" is precisely what a VoiceOver user needs from a
//  three-way toggle. The write still runs through this file's own setter
//  — see `select(_:)` — because the binding handed to the picker is
//  derived rather than passed straight through, so the haptic and the
//  Reduce Motion-aware animation happen on every change including the
//  ones the system initiates.
//

import SwiftUI

/// Switches the closet between spec §6.14's editorial grid, compact list
/// and colour spectrum.
struct ClosetViewModeToggle: View {

    @Binding private var selection: ClosetViewMode
    /// Cut-outs share this menu rather than taking a fifth glyph on a header
    /// row this file's neighbour already documents as barely fitting four.
    /// They belong together anyway: both are "how the closet looks", neither
    /// touches what is in it.
    @Binding private var showsCutouts: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selection: Binding<ClosetViewMode>, showsCutouts: Binding<Bool>) {
        _selection = selection
        _showsCutouts = showsCutouts
    }

    var body: some View {
        Menu {
            Picker(selection: modeBinding) {
                ForEach(ClosetViewMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.symbolName)
                        .tag(mode)
                }
            } label: {
                Text(String(localized: "View", comment: "Title of the closet layout menu"))
            }
            .pickerStyle(.inline)

            Divider()

            Toggle(isOn: $showsCutouts) {
                Label(
                    String(localized: "Cut Out Backgrounds", comment: "Closet display toggle"),
                    systemImage: "person.and.background.dotted"
                )
            }
            .accessibilityHint(Text(String(
                localized: "Shows garments cut out from their backgrounds. Turn off to see the photographs as you took them.",
                comment: "VoiceOver hint for the closet cut-out toggle"
            )))
        } label: {
            Image(systemName: selection.symbolName)
                .astraIcon(.emphasis)
                // An icon is a fill, not text, so this is the plain
                // champagne token — the same call the add and scan
                // buttons beside it make (spec §3 / docs/07).
                .foregroundStyle(AstraColor.accentChampagne)
                .frame(minWidth: AstraSize.minTapTarget, minHeight: AstraSize.minTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(String(localized: "View", comment: "VoiceOver label for the closet layout control")))
        // The value, not the label, so VoiceOver says which layout is on
        // rather than making the user open the menu to find out.
        .accessibilityValue(Text(selection.displayName))
        .accessibilityHint(Text(String(localized: "Changes how your closet is laid out", comment: "VoiceOver hint for the closet layout control")))
        .accessibilityIdentifier("closet.header.viewMode")
    }

    /// A derived binding so every write — including the picker's own —
    /// goes through `select(_:)`.
    ///
    /// Passing `$selection` straight to the picker would work and would
    /// silently skip the haptic and the animation, which is the kind of
    /// gap that only shows up when someone notices the mode changing with
    /// no feedback months later.
    private var modeBinding: Binding<ClosetViewMode> {
        Binding(get: { selection }, set: { select($0) })
    }

    /// Applies a mode change.
    ///
    /// `AstraHaptics.selection()` is spec §3's mapping for a lightweight
    /// selection change, which is what this is.
    ///
    /// The animation is applied HERE rather than left to the screen that
    /// swaps the views, so that the transition between two layouts is
    /// Reduce Motion-aware wherever this control is used. Under Reduce
    /// Motion `AstraMotion.aware(_:reduceMotion:)` returns `nil` and the
    /// swap happens immediately, with no cross-fade of two full grids —
    /// which is the animation most worth suppressing on this screen.
    private func select(_ mode: ClosetViewMode) {
        guard mode != selection else { return }
        AstraHaptics.selection()
        withAnimation(AstraMotion.aware(AstraMotion.standard, reduceMotion: reduceMotion)) {
            selection = mode
        }
    }
}

// MARK: - Previews

private struct ClosetViewModeTogglePreview: View {
    @State private var mode: ClosetViewMode = .editorialGrid
    @State private var showsCutouts = true

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            // The real header shape: a display-weight title and three
            // glyph controls sharing one row.
            HStack(alignment: .firstTextBaseline, spacing: AstraSpacing.sm) {
                Text(verbatim: "My Closet")
                    .astraText(.displayL)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: AstraSpacing.sm)

                ClosetViewModeToggle(selection: $mode, showsCutouts: $showsCutouts)
                Image(systemName: "plus")
                    .astraIcon(.emphasis)
                    .foregroundStyle(AstraColor.accentChampagne)
                Image(systemName: "camera.viewfinder")
                    .astraIcon(.emphasis)
                    .foregroundStyle(AstraColor.accentChampagne)
            }

            Text(mode.displayName)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AstraColor.backgroundPrimary)
    }
}

#Preview("View mode toggle") {
    ClosetViewModeTogglePreview()
        .preferredColorScheme(.dark)
}

/// The size the header row is tightest at, and the reason this control is
/// a menu rather than three chips.
#Preview("View mode toggle — accessibility 5") {
    ClosetViewModeTogglePreview()
        .environment(\.dynamicTypeSize, .accessibility5)
        .preferredColorScheme(.light)
}
