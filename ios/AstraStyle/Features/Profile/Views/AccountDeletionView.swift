//
//  AccountDeletionView.swift
//  AstraStyle
//
//  P7-PRIVACY-02: the deliberate confirmation flow `DELETE /account`
//  needs. Reached by `ProfileRoute.accountDeletion`, pushed from
//  `PrivacyAndDataView` — never a single tap behind a chevron. App Store
//  Guideline 5.1.1(v) requires the deletion path be reachable in a few
//  taps; it does not require the LAST tap be unguarded, and destroying a
//  wardrobe someone spent an hour photographing should not survive a
//  mis-tap.
//
//  TWO DELIBERATE STEPS IN FRONT OF THE DESTRUCTIVE CALL, NOT ONE.
//  1. A toggle the user must turn on by hand, beside the inventory of
//     what is destroyed — so scrolling past the list and mashing a button
//     is not enough; he has to affirmatively agree to something he just
//     read.
//  2. Only then does the destructive button do anything, and what it does
//     is open a `.confirmationDialog` with its own destructive-role
//     button — the same second-step pattern
//     `ClosetItemActionRow`'s archive button uses, one level higher
//     because this action cannot be undone at all.
//
//  THE INVENTORY BELOW IS TRANSCRIBED, NOT WRITTEN. Every bullet maps
//  onto a table `supabase/migrations/20260728101300_account_deletion.sql`'s
//  header comment names as covered by the `auth.admin.deleteUser` cascade
//  (step 5), plus the Storage API sweep from that same file's step 3.
//  Nothing here is invented, and nothing that migration lists is left
//  off.
//
//  THIS SCREEN NEVER SAYS "DELETED". See `AccountDeletionViewModel`'s
//  header — the server can only ever answer "accepted and in progress",
//  and this view says exactly that, not more.
//

import SwiftUI

struct AccountDeletionView: View {
    @State private var viewModel: AccountDeletionViewModel
    @State private var isConfirmingDelete = false
    @Environment(AppRouter.self) private var router

    init(viewModel: AccountDeletionViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                switch viewModel.phase {
                case .confirming, .deleting:
                    reviewContent
                case .started(let status):
                    startedContent(status)
                case .failed(let error):
                    reviewContent
                    failureContent(error)
                }
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
            .padding(.vertical, AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationTitle(String(localized: "Delete Account", comment: "Account deletion screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isStarted)
        .confirmationDialog(
            Text(dialogTitle),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(deleteConfirmTitle, role: .destructive) {
                Task { await viewModel.delete() }
            }
            Button(cancelTitle, role: .cancel) {}
        } message: {
            Text(dialogMessage)
        }
    }

    // MARK: - Reviewing

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xl) {
            reviewHeader
            inventoryCard
            acknowledgmentToggle
            deleteButton
        }
    }

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(String(localized: "PERMANENT", comment: "Eyebrow label above the account deletion warning"))
                .astraText(.micro)
                .foregroundStyle(AstraColor.destructive)
            Text(String(localized: "Delete your account", comment: "Account deletion screen headline"))
                .astraText(.title1)
                .foregroundStyle(AstraColor.textPrimary)
            Text(String(
                localized: "This permanently removes your Astra Style account. It cannot be undone.",
                comment: "Account deletion screen subhead"
            ))
            .astraText(.body)
            .foregroundStyle(AstraColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inventoryCard: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(String(localized: "What gets deleted", comment: "Header above the account deletion inventory list"))
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                ForEach(Self.deletionInventory, id: \.self) { line in
                    inventoryRow(line)
                }
            }
        }
    }

    private func inventoryRow(_ line: String) -> some View {
        HStack(alignment: .top, spacing: AstraSpacing.xs) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(AstraColor.textMuted)
                .padding(.top, AstraSpacing.xs)
                .accessibilityHidden(true)
            Text(line)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var acknowledgmentToggle: some View {
        Button {
            viewModel.hasAcknowledgedIrreversibility.toggle()
            AstraHaptics.selection()
        } label: {
            HStack(alignment: .top, spacing: AstraSpacing.md) {
                Image(systemName: viewModel.hasAcknowledgedIrreversibility ? "checkmark.circle.fill" : "circle")
                    .astraIcon(.emphasis)
                    .foregroundStyle(
                        viewModel.hasAcknowledgedIrreversibility
                            ? AstraColor.destructive
                            : AstraColor.textMuted
                    )
                    .accessibilityHidden(true)
                Text(String(
                    localized: "I understand this is permanent and cannot be undone.",
                    comment: "Account deletion acknowledgment toggle"
                ))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AstraSpacing.md)
            .frame(minHeight: AstraSize.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .fill(AstraColor.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .strokeBorder(
                        viewModel.hasAcknowledgedIrreversibility
                            ? AstraColor.destructive
                            : AstraColor.divider,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.phase == .deleting)
        .accessibilityIdentifier("accountDeletion.acknowledgeToggle")
        .accessibilityAddTraits(viewModel.hasAcknowledgedIrreversibility ? .isSelected : AccessibilityTraits())
        .accessibilityHint(Text(String(
            localized: "Required before the delete control can run.",
            comment: "Account deletion acknowledgment hint"
        )))
    }

    /// Not `.astraPrimary`: champagne is this app's "yes/continue" color
    /// (`AstraButton`'s own doc comment), and irreversibly destroying a
    /// wardrobe is not that. Not a filled destructive background either —
    /// no Astra token documents a text-on-destructive-fill contrast pair,
    /// while `AstraColor.destructive` as a TEXT/border color on
    /// `backgroundPrimary` is the already-vetted pattern
    /// (`ClosetItemActionRow`'s archive button, `SignedOutGateView`'s
    /// auth error text). This mirrors `AstraSecondaryButtonStyle`'s
    /// bordered shape with that color instead of champagne, so it reads
    /// as the one thing this screen exists to do without inventing an
    /// unvetted color combination.
    private var deleteButton: some View {
        Button {
            AstraHaptics.warning()
            isConfirmingDelete = true
        } label: {
            Group {
                if viewModel.phase == .deleting {
                    ProgressView()
                        .tint(AstraColor.destructive)
                        .accessibilityLabel(Text(deleteButtonTitle))
                } else {
                    Text(deleteButtonTitle)
                }
            }
            .astraText(.headline)
            .foregroundStyle(AstraColor.destructive)
            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.button, style: .continuous)
                    .strokeBorder(AstraColor.destructive, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(viewModel.hasAcknowledgedIrreversibility ? 1 : 0.45)
        .disabled(!viewModel.hasAcknowledgedIrreversibility || viewModel.phase == .deleting)
        .accessibilityIdentifier("accountDeletion.deleteButton")
        .accessibilityHint(Text(deleteButtonHint))
    }

    // MARK: - Failure

    @ViewBuilder
    private func failureContent(_ error: AstraError) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(String(localized: "Couldn't start deletion", comment: "Account deletion failure headline"))
                .astraText(.headline)
                .foregroundStyle(AstraColor.destructive)
            // `AstraError.message` is already user-facing copy — rendered
            // as-is, matching `ClosetItemDetailView`'s alert.
            Text(error.message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Started

    @ViewBuilder
    private func startedContent(_ status: AccountDeletionStatus) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xl) {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(String(localized: "IN PROGRESS", comment: "Eyebrow label once account deletion has started"))
                    .astraText(.micro)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                Text(startedHeadline(for: status))
                    .astraText(.title1)
                    .foregroundStyle(AstraColor.textPrimary)
                Text(String(
                    localized: "Your account and everything in it are being permanently deleted. This can't be undone or cancelled, and you've been signed out.",
                    comment: "Account deletion started confirmation body"
                ))
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            AstraButton(title: String(
                localized: "Done",
                comment: "Acknowledges the account deletion has started and returns to sign-in"
            )) {
                router.routeState = .signedOut
            }
            .accessibilityIdentifier("accountDeletion.doneButton")
        }
    }

    /// Handles the endpoint's documented idempotency: a retried DELETE
    /// call, or a second visit to this screen, finds the SAME job already
    /// underway rather than erroring — see `account/handler.ts`'s
    /// "idempotent_replay" path. Either way the account is being deleted;
    /// only the wording changes, and only to stay honest about which is
    /// true.
    private func startedHeadline(for status: AccountDeletionStatus) -> String {
        switch status.status {
        case .pending:
            String(localized: "Deletion has started", comment: "Headline when this call began the deletion")
        case .processing:
            String(
                localized: "Deletion is already underway",
                comment: "Headline when a deletion job was already running before this call"
            )
        }
    }

    private var isStarted: Bool {
        if case .started = viewModel.phase { return true }
        return false
    }

    // MARK: - Inventory copy

    /// One bullet per table/storage path the migration's header comment
    /// names — see this file's header for why nothing here is invented.
    private static let deletionInventory: [String] = [
        String(localized: "Your profile, Style DNA, body measurements, and lifestyle preferences", comment: "Deletion inventory: profile tables"),
        String(localized: "Every closet item and its photos", comment: "Deletion inventory: closet"),
        String(localized: "Every outfit and its wear history", comment: "Deletion inventory: outfits"),
        String(localized: "Your style feedback and style memories, including their embeddings", comment: "Deletion inventory: style memories"),
        String(localized: "Your Kyra conversation threads and messages", comment: "Deletion inventory: Kyra"),
        String(localized: "Occasions and Daily Briefs", comment: "Deletion inventory: occasions and briefs"),
        String(localized: "Style Studio generations", comment: "Deletion inventory: studio"),
        String(localized: "Your subscription record", comment: "Deletion inventory: subscription"),
        String(localized: "Product evaluations you've saved", comment: "Deletion inventory: product evaluations"),
        String(
            localized: "Every photo in storage: closet photos, reference photos, and Style Studio images",
            comment: "Deletion inventory: storage objects"
        )
    ]

    // MARK: - Copy

    private var dialogTitle: String {
        String(localized: "Delete your account?", comment: "Account deletion confirmation dialog title")
    }

    private var dialogMessage: String {
        String(
            localized: "This starts permanent deletion of your account and everything in it. It cannot be cancelled once it begins.",
            comment: "Account deletion confirmation dialog message"
        )
    }

    private var deleteConfirmTitle: String {
        String(localized: "Delete Permanently", comment: "Destructive confirmation button")
    }

    private var cancelTitle: String {
        String(localized: "Cancel", comment: "Dismisses the account deletion confirmation dialog")
    }

    private var deleteButtonTitle: String {
        String(localized: "Delete My Account", comment: "Primary destructive action opening the final confirmation")
    }

    private var deleteButtonHint: String {
        String(localized: "Asks you to confirm first", comment: "Accessibility hint on the delete-account button")
    }
}
