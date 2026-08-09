//
//  ClosetLaundryAlertView.swift
//  AstraStyle
//
//  Spec §6.11 listed the laundry alert as a Home module, and that is where
//  it was built. Home is now one look — the outfit you are being told to
//  wear — and a washing-machine count sitting under it answered a question
//  nobody had opened Home to ask. It moved here, to the screen the garments
//  themselves live on.
//
//  IT ANSWERS "WHICH ONES", NOT "HOW MANY", AND THAT IS THE WHOLE CHANGE.
//  The Home version was a button that said "4 items currently in the
//  laundry" and pushed the Closet tab. Arriving there, the user still had
//  to find the four. This row names them, in place, on tap.
//
//  It deliberately does NOT apply a closet filter, and the reason is
//  concrete rather than stylistic. `ClosetFilters` has an `availability`
//  facet and no laundry facet, and `availability_state` is a different
//  column from `laundry_state`: `LiveClosetRepository.updateLaundryState`
//  writes only the latter, so nothing in the app ever moves a garment to
//  `.inLaundry` availability. A tap that set `availability: [.inLaundry]`
//  would narrow a closet of forty garments down to nothing directly
//  beneath a line reading "4 items currently in the laundry" — a control
//  that contradicts its own label. The server is right about this and
//  always has been (`daily-brief/index.ts` filters on BOTH columns); it is
//  only the client's filter vocabulary that has one of the two.
//
//  Expanding in place also avoids re-narrowing the whole screen for a
//  question that takes four rows to answer, and leaves nothing for the
//  user to undo afterwards.
//

import SwiftUI

/// The laundry disclosure, drawn only when something is actually in the wash.
///
/// The caller decides whether to draw it at all — an alert reading "0 items"
/// is the §22 dead control, and the empty case here is genuinely nothing to
/// say rather than a state worth rendering.
struct ClosetLaundryAlertView: View {
    let items: [ClosetItem]
    let onSelect: (UUID) -> Void

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: 0) {
                summaryRow
                if isExpanded {
                    Divider()
                        .overlay(AstraColor.divider)
                        .padding(.vertical, AstraSpacing.sm)
                    garmentRows
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .accessibilityIdentifier("closet.laundryAlert")
    }

    private var summaryRow: some View {
        Button {
            withAnimation(AstraMotion.aware(AstraMotion.standard, reduceMotion: reduceMotion)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: AstraSpacing.sm) {
                Image(systemName: "washer")
                    .foregroundStyle(AstraColor.warningAmber)
                Text(message)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: AstraSpacing.sm)
                Image(systemName: "chevron.down")
                    .astraIcon(.disclosure)
                    .foregroundStyle(AstraColor.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(message))
        .accessibilityHint(Text(isExpanded
            ? String(localized: "Hides the list", comment: "Laundry alert collapse hint")
            : String(localized: "Lists which pieces they are", comment: "Laundry alert expand hint")))
        .accessibilityIdentifier("closet.laundryAlert.toggle")
    }

    private var garmentRows: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            ForEach(items) { item in
                Button {
                    onSelect(item.id)
                } label: {
                    HStack(spacing: AstraSpacing.sm) {
                        Text(item.name)
                            .astraText(.body)
                            .foregroundStyle(AstraColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: AstraSpacing.sm)
                        Image(systemName: "chevron.right")
                            .astraIcon(.disclosure)
                            .foregroundStyle(AstraColor.textMuted)
                    }
                    .frame(minHeight: AstraSize.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var message: String {
        String(
            localized: "^[\(items.count) item](inflect: true) in the wash",
            comment: "Closet laundry alert summary"
        )
    }
}
