//
//  ClosetItemActionRow.swift
//  AstraStyle
//
//  Spec §6.15 "Actions": mark worn, add to laundry, edit, archive.
//
//  WHAT IS NOT HERE. §6.15's fifth action is "Sell/donate later" — the
//  word "later" is the spec deferring it, and there is no resale or
//  donation surface, no `availability_state` transition for it, and no
//  screen behind it. A greyed-out button for it would be exactly the dead
//  button spec §22's acceptance bar names. It is absent, not disabled.
//
//  WHY LAUNDRY IS A BUTTON HERE AND A PICKER ON THE FIELD ROW. This
//  control is used in the ninety seconds after a man takes a shirt off: it
//  wants to be one tap, reachable one-handed, and reversible. `LaundryState`
//  has four cases, but only one of them is that reflex. So the row toggles
//  between "Into the wash" and "Out of the wash", and the other two states
//  ("Worn once" for the shirt going back on the hanger, "Unavailable" for
//  the jacket at the tailor) live on the laundry field row, where they read
//  as corrections rather than as three-quarters of a menu he has to dismiss
//  every morning.
//
//  EVERY ACTION HAS A LOADING STATE AND A FAILURE PATH. The in-flight
//  booleans come in from the view model — one per action, so tapping
//  Mark worn does not grey out Edit — and the failure path is the alert
//  `ClosetItemDetailView` raises from `actionError`, plus the visible
//  rollback of the optimistic edit. Nothing here taps into silence.
//

import SwiftUI

struct ClosetItemActionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isConfirmingArchive = false

    let laundryState: LaundryState
    let isMarkingWorn: Bool
    let isUpdatingLaundryState: Bool
    let isArchiving: Bool
    let onMarkWorn: () -> Void
    let onSetLaundryState: (LaundryState) -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void

    var body: some View {
        VStack(spacing: AstraSpacing.sm) {
            AstraButton(title: markWornTitle, isLoading: isMarkingWorn, action: onMarkWorn)

            secondaryActions

            archiveButton
        }
        .confirmationDialog(
            Text(confirmArchiveTitle),
            isPresented: $isConfirmingArchive,
            titleVisibility: .visible
        ) {
            Button(archiveTitle, role: .destructive, action: onArchive)
            Button(cancelTitle, role: .cancel) {}
        } message: {
            Text(confirmArchiveMessage)
        }
    }

    /// Side by side at ordinary text sizes, stacked at accessibility sizes.
    /// Two `maxWidth: .infinity` buttons sharing a row at AX5 leaves each
    /// about 90 pt of usable width, which truncates "Out of the wash"
    /// rather than wrapping it.
    @ViewBuilder
    private var secondaryActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AstraSpacing.sm) {
                laundryButton
                editButton
            }
        } else {
            HStack(spacing: AstraSpacing.sm) {
                laundryButton
                editButton
            }
        }
    }

    private var laundryButton: some View {
        Button {
            onSetLaundryState(laundryState == .laundry ? .clean : .laundry)
        } label: {
            if isUpdatingLaundryState {
                ProgressView()
                    .tint(AstraColor.accentChampagneAccessible)
                    .accessibilityLabel(Text(laundryTitle))
            } else {
                Text(laundryTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.astraSecondary)
        .disabled(isUpdatingLaundryState)
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Text(editTitle)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.astraSecondary)
    }

    /// Not `.astraTertiary`: that style is champagne, and champagne is this
    /// app's "yes" colour. A destructive action gets `AstraColor.destructive`
    /// (spec §3), which no Astra button style provides, so this one is built
    /// from a plain button plus the token — still 44 pt, still full width.
    private var archiveButton: some View {
        Button {
            // Spec §3 maps `.warning` to destructive actions, and fires it
            // BEFORE the confirmation rather than after it: the point of the
            // haptic is to make the destructive branch feel different from
            // the other three the instant it is entered.
            AstraHaptics.warning()
            isConfirmingArchive = true
        } label: {
            Group {
                if isArchiving {
                    ProgressView()
                        .tint(AstraColor.destructive)
                        .accessibilityLabel(Text(archiveTitle))
                } else {
                    Label(archiveTitle, systemImage: "archivebox")
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
            }
            .astraText(.headline)
            .foregroundStyle(AstraColor.destructive)
            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isArchiving)
        .accessibilityHint(Text(archiveHint))
    }

    // MARK: - Copy

    private var markWornTitle: String {
        String(localized: "Mark worn", comment: "Records that the user wore this garment today")
    }

    private var laundryTitle: String {
        laundryState == .laundry
            ? String(localized: "Out of the wash", comment: "Returns a garment from the laundry to the wardrobe")
            : String(localized: "Into the wash", comment: "Puts a garment into the laundry")
    }

    private var editTitle: String {
        String(localized: "Edit", comment: "Opens the garment editor")
    }

    private var archiveTitle: String {
        String(localized: "Archive", comment: "Removes a garment from the closet views without deleting it")
    }

    private var cancelTitle: String {
        String(localized: "Cancel", comment: "Dismisses the archive confirmation")
    }

    private var archiveHint: String {
        String(localized: "Asks you to confirm first", comment: "Accessibility hint on the archive button")
    }

    private var confirmArchiveTitle: String {
        String(localized: "Archive this piece?", comment: "Archive confirmation title")
    }

    /// Says what archiving does AND what it does not do. "Archive" reads as
    /// a soft word for delete to most people, and this is the one moment to
    /// correct that — the row is kept (spec §9 soft deletion), the garment
    /// simply stops appearing in the closet and in outfit suggestions.
    ///
    /// It deliberately does NOT promise "you can bring it back". Un-archiving
    /// has no screen behind it yet, and a confirmation dialog is the wrong
    /// place to describe a path that does not exist.
    private var confirmArchiveMessage: String {
        String(
            localized: "It stops appearing in your closet and in Kyra's outfits. Nothing is deleted — its wear history is kept.",
            comment: "Archive confirmation message explaining that archiving is a soft delete"
        )
    }
}
