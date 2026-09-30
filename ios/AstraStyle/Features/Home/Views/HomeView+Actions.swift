//
//  HomeView+Actions.swift
//  AstraStyle
//

import SwiftUI

extension HomeView {
    func actions(for data: HomeBriefData) -> some View {
        VStack(spacing: AstraSpacing.sm) {
            AstraButton(
                title: wearThisTitle,
                isLoading: viewModel.isMarkingWorn
            ) {
                markWorn()
            }
            .disabled(viewModel.hasMarkedWorn)
            .accessibilityIdentifier("home.wearThis")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AstraSpacing.sm) {
                    somethingElseButton
                    seeOnYouButton
                }
                VStack(spacing: AstraSpacing.sm) {
                    somethingElseButton
                    seeOnYouButton
                }
            }

            if let confirmation = homeFeedbackConfirmation {
                Text(confirmation)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("home.feedback.confirmation")
            }

            Menu {
                Button {
                    isPastingLink = true
                } label: {
                    Label(
                        String(localized: "Check a product link", comment: "Home utility menu paste-link action"),
                        systemImage: "link"
                    )
                }
                .accessibilityIdentifier("home.pasteLink")
                todayShareMenuItem
                homeSkipDislikeItems(for: data)
            } label: {
                Label(
                    String(localized: "More options", comment: "Home utility actions menu"),
                    systemImage: "ellipsis"
                )
                .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            }
            .buttonStyle(.astraTertiary)
            .accessibilityIdentifier("home.moreOptions")

            makePublicOffer
        }
    }

    @ViewBuilder
    func homeSkipDislikeItems(for data: HomeBriefData) -> some View {
        if data.primaryOutfit != nil, wearFeedbackViewModel != nil {
            Button {
                Task { await wearFeedbackViewModel?.skip() }
            } label: {
                Label(
                    String(localized: "Not today", comment: "Home skip today's look"),
                    systemImage: "arrow.uturn.forward"
                )
            }
            .accessibilityIdentifier("home.skip")

            Button {
                Task { await wearFeedbackViewModel?.dislike() }
            } label: {
                Label(
                    String(localized: "Don't show this again", comment: "Home dislike today's look"),
                    systemImage: "hand.thumbsdown"
                )
            }
            .accessibilityIdentifier("home.dislike")
        }
    }

    var homeFeedbackConfirmation: String? {
        guard let outcome = wearFeedbackViewModel?.lastOutcome else { return nil }
        switch outcome {
        case .wore:
            return String(localized: "Logged as worn today.", comment: "Home wear confirmation")
        case .feedback(.skipped):
            return String(localized: "Noted — skipped.", comment: "Home skip confirmation")
        case .feedback(.dislike):
            return String(localized: "Noted — Kyra will factor this in.", comment: "Home dislike confirmation")
        case .feedback:
            return String(localized: "Feedback recorded.", comment: "Home feedback confirmation")
        }
    }

    func syncWearFeedback(for data: HomeBriefData) {
        guard let outfitID = data.primaryOutfit?.id else {
            wearFeedbackViewModel = nil
            return
        }
        if wearFeedbackViewModel?.outfitID != outfitID {
            wearFeedbackViewModel = WearFeedbackViewModel(
                outfitID: outfitID,
                outfitRepository: container.outfitRepository,
                analyticsClient: container.analyticsClient
            )
        }
    }

    var somethingElseButton: some View {
        Button {
            // The carousel lives in the Closet, where browsing belongs.
            // Home's job is to have decided; this is the door out of that
            // decision, not a second one on the same screen.
            router.select(.closet)
        } label: {
            Text(String(localized: "Something Else", comment: "Home secondary action"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.astraSecondary)
        .accessibilityHint(Text(String(
            localized: "Browse other outfits in your closet",
            comment: "VoiceOver hint for the Home alternatives action"
        )))
        .accessibilityIdentifier("home.somethingElse")
    }

    @ViewBuilder
    var seeOnYouButton: some View {
        if case .loaded(let data) = viewModel.state, data.primaryOutfit != nil {
            Button {
                router.presentModal(.studioGeneration(outfitID: data.primaryOutfit?.id))
            } label: {
                Text(String(localized: "See on you", comment: "Home door into Studio for today's look"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("home.seeOnYou")
        }
    }

    /// System share of today's look name + why. Not a feed.
    @ViewBuilder
    var todayShareMenuItem: some View {
        if case .loaded(let data) = viewModel.state, let outfit = data.primaryOutfit {
            let why = data.brief.kyraMessage ?? outfit.description
            ShareLink(item: HomeShareCopy.shareText(name: outfit.name, why: why)) {
                Label(
                    String(localized: "Share this look", comment: "Home share of today's look"),
                    systemImage: "square.and.arrow.up"
                )
            }
            .accessibilityIdentifier("home.shareLook")
        }
    }

    /// Empty Home still needs a direct don't-buy door because there is no
    /// outfit action menu yet. On loaded Home this same action moves under
    /// More options to preserve the single-decision hierarchy.
    var pasteLinkButton: some View {
        Button {
            isPastingLink = true
        } label: {
            Text(String(localized: "Check a product link", comment: "Home paste-a-link don't-buy door"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.astraSecondary)
        .accessibilityIdentifier("home.pasteLink")
    }

    /// Opt-in after Wear This. Never auto-publishes the closet.
    @ViewBuilder
    var makePublicOffer: some View {
        if viewModel.canOfferPublicLook {
            Button {
                isConfirmingPublicLook = true
            } label: {
                Text(LookbookSharingCopy.actionTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("home.makeLookPublic")
        }
    }

    /// Haptics live here, not in the view model — same rule as
    /// `OutfitDetailView.markWorn()` so a unit test never reaches for the
    /// Taptic Engine, and success fires on the write, not the tap.
    func markWorn() {
        Task {
            await viewModel.markPrimaryOutfitWorn()
            if viewModel.actionError == nil, viewModel.hasMarkedWorn {
                AstraHaptics.success()
            }
        }
    }

    var wearThisTitle: String {
        viewModel.hasMarkedWorn
            ? String(localized: "Worn today", comment: "Home Wear This after a successful write")
            : String(localized: "Wear This", comment: "Home primary action")
    }

    var actionFailureTitle: String {
        String(localized: "Couldn't record that", comment: "Home Wear This failure alert title")
    }

    var dismissTitle: String {
        String(localized: "OK", comment: "Dismisses the Home Wear This failure alert")
    }

    var actionErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.actionError != nil },
            set: { isPresented in
                if !isPresented { viewModel.clearActionError() }
            }
        )
    }

}
