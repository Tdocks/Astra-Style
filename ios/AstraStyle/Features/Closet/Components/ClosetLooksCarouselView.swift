//
//  ClosetLooksCarouselView.swift
//  AstraStyle
//
//  "A carousel of outfits so I can scroll through and go 'oh, I like that',
//  click on it, and it tells me which of my clothing articles to grab."
//
//  Each card is a whole outfit stacked head to toe (`LookSilhouetteView`),
//  proportioned to the wearer's frame, made of his own garments' cut-outs.
//  Tapping one opens outfit detail, which is where the grab-list lives —
//  that screen already exists and already names every piece.
//
//  PAGING, NOT FREE SCROLL. `.scrollTargetBehavior(.viewAligned)` settles
//  on a card rather than leaving one half off the edge, which is what makes
//  the tone controls beneath it meaningful: they act on the look in front
//  of him, so there has to be exactly one look in front of him.
//
//  The card width leaves the next card visibly peeking. A carousel whose
//  second item is fully off-screen reads as a static card and does not get
//  swiped — the affordance has to be visible before the gesture is.
//

import SwiftUI

struct ClosetLooksCarouselView: View {
    let viewModel: ClosetLooksViewModel
    let onOpenLook: (UUID) -> Void
    let onOpenGarment: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            switch viewModel.state {
            case .loading:
                header
                placeholderCard
            case .loaded(let looks):
                header
                carousel(looks)
                toneControls
            case .empty:
                header
                emptyLine
            case .failed(let error):
                header
                failureLine(error)
            }
        }
        .accessibilityIdentifier("closet.looks")
    }

    private var header: some View {
        Text(String(localized: "Looks", comment: "Closet outfit carousel heading"))
            .astraText(.headline)
            .foregroundStyle(AstraColor.textPrimary)
            .padding(.horizontal, AstraSpacing.pagePadding)
    }

    private func carousel(_ looks: [ClosetLooksViewModel.Look]) -> some View {
        @Bindable var model = viewModel
        return ScrollView(.horizontal) {
            LazyHStack(spacing: AstraSpacing.md) {
                ForEach(looks) { look in
                    card(look)
                        .id(look.id)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $model.focusedLookID, anchor: .center)
    }

    private func card(_ look: ClosetLooksViewModel.Look) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            LookSilhouetteView(
                garments: look.garments,
                frame: viewModel.frame,
                onTapGarment: { onOpenGarment($0.item.id) }
            )

            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(look.outfit.name)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // The day it was built, because the server names every
                // generated outfit "Today's Outfit" — four cards carrying
                // the same three words are four cards the user cannot tell
                // apart or refer to. The date is the one thing that
                // genuinely differs and it is already on the row.
                Text(AstraDateFormatting.longWeekdayAndDate(look.outfit.createdAt))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onOpenLook(look.outfit.id)
            } label: {
                Text(String(localized: "What to grab", comment: "Carousel card action"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("closet.looks.open")
        }
        .frame(width: AstraSize.silhouetteCardWidth)
    }

    private var toneControls: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            HStack(spacing: AstraSpacing.sm) {
                toneButton(.tooDressy, title: String(
                    localized: "Too dressy",
                    comment: "Carousel tone control"
                ))
                toneButton(.tooCasual, title: String(
                    localized: "Too casual",
                    comment: "Carousel tone control"
                ))
            }

            // Only ever set when a nudge had nowhere to go — see
            // `ClosetLooksViewModel.nudgeNote`.
            if let note = viewModel.nudgeNote {
                Text(note)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("closet.looks.nudgeNote")
            }
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
    }

    private func toneButton(_ tone: ClosetLooksViewModel.ToneNudge, title: String) -> some View {
        Button {
            Task { await viewModel.nudge(tone) }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.astraSecondary)
    }

    private var placeholderCard: some View {
        RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
            .fill(AstraColor.surfaceElevated)
            .frame(width: AstraSize.silhouetteCardWidth, height: AstraSize.silhouetteHeight)
            .padding(.horizontal, AstraSpacing.pagePadding)
            .accessibilityHidden(true)
    }

    /// Absent is honest: no looks yet is not a failure and is not the user's
    /// fault, and the line says what will change it rather than offering a
    /// button that would build one now — there is no client-side generate
    /// path that persists an outfit, so such a button could not work.
    private var emptyLine: some View {
        Text(String(
            localized: "Kyra builds looks each morning from what's in here. Once she has, they'll show up.",
            comment: "Closet carousel empty state"
        ))
            .astraText(.body)
            .foregroundStyle(AstraColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AstraSpacing.pagePadding)
    }

    private func failureLine(_ error: AstraError) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(error.message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if error.isRetryable {
                Button {
                    Task { await viewModel.reload() }
                } label: {
                    Text(String(localized: "Try Again", comment: "Closet carousel retry"))
                }
                .buttonStyle(.astraSecondary)
            }
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
    }
}
