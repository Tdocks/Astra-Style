//
//  OutfitCompatibilityMeterView.swift
//  AstraStyle
//
//  Spec §6.13's live compatibility meter, wrapping `AstraScoreMeter`.
//
//  THE ABSENT STATE IS DRAWN, NOT HIDDEN. `OutfitBuilderViewModel
//  .currentCompatibility` is `nil` below two filled slots — see that
//  property's own header for why a single garment has nothing to be
//  compatible WITH. The naive reading of that is "don't show the meter",
//  but an view that simply omits the module below two items looks
//  identical to one that forgot to build it at all, and a user who has
//  filled one slot gets no feedback that the SECOND slot is what will
//  make the number appear. So this always renders something: the real
//  meter once there is a real reading, and an explicit "add another
//  piece" placeholder in the exact same layout slot otherwise — the
//  "absent is honest" rule applied to a view, not only to a view model.
//

import SwiftUI

struct OutfitCompatibilityMeterView: View {
    let breakdown: CompatibilityBreakdown?

    var body: some View {
        Group {
            if let breakdown {
                AstraScoreMeter(score: breakdown.score(), title: meterTitle, style: .compact)
            } else {
                placeholder
            }
        }
        .accessibilityIdentifier("outfitBuilder.compatibilityMeter")
    }

    private var placeholder: some View {
        HStack(spacing: AstraSpacing.sm) {
            Image(systemName: "circle.dashed")
                .astraIcon(.emphasis)
                .foregroundStyle(AstraColor.textMuted)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(meterTitle)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                Text(placeholderCopy)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(meterTitle): \(placeholderCopy)"))
    }

    private var meterTitle: String {
        String(localized: "Compatibility", comment: "Label above the outfit builder's live compatibility meter")
    }

    private var placeholderCopy: String {
        String(localized: "Add another piece to see this", comment: "Shown instead of a compatibility score when fewer than two slots are filled")
    }
}

#Preview("Meter states") {
    VStack(alignment: .leading, spacing: AstraSpacing.lg) {
        OutfitCompatibilityMeterView(breakdown: nil)
        OutfitCompatibilityMeterView(
            breakdown: CompatibilityBreakdown(
                colorCompatibility: 0.8,
                formalityAlignment: 0.7,
                silhouetteCompatibility: 0.6,
                seasonWeatherSuitability: 0.6,
                userPreference: 0.6,
                historicalCoWear: 0.6,
                occasionRelevance: 0.6,
                availabilityLaundry: 1
            )
        )
    }
    .padding(AstraSpacing.pagePadding)
    .background(AstraColor.backgroundPrimary)
    .preferredColorScheme(.dark)
}
