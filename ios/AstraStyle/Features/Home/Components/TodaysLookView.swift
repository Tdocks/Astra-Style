//
//  TodaysLookView.swift
//  AstraStyle
//
//  The clothes, on the screen, at last.
//
//  This replaces `HeroOutfitCardView`'s hero image, which rendered
//  `outfit.heroImageURL ?? outfit.generatedPreviewURL` — two fields nothing
//  in the app has ever written. `hero_image_url` occurs exactly once in the
//  codebase, as a `CodingKey`; `generatedPreviewURL` comes from Style Studio,
//  which is not built. So the largest element on Home was a permanent
//  placeholder, drawn above a garment list the app had already fetched and
//  was throwing away.
//
//  The layout is the owner's own mock: garments laid out on the dark ground,
//  the top largest and the rest ranged beside it, the way a man lays clothes
//  on a bed the night before. It is not a grid of equal tiles, because an
//  outfit is not a set of equal things — the shirt is the decision and the
//  watch is a detail, and a layout that gives them the same square says
//  otherwise.
//
//  It works because every garment scanned since `BackgroundRemoval` shipped
//  has a cut-out on transparency. A raw photograph in one of these slots
//  still renders — it just brings its own background with it, which is
//  exactly the visible difference the cut-out toggle exists to let a man
//  judge for himself.
//

import SwiftUI

struct TodaysLookView: View {
    let garments: [LookGarment]

    /// Tapping a garment goes to it. The look is made of real things the man
    /// owns, and the whole point of showing them is that they are reachable.
    var onTapGarment: (LookGarment) -> Void

    var body: some View {
        VStack(spacing: AstraSpacing.md) {
            if let anchor {
                garmentTile(anchor, height: AstraSize.lookAnchorHeight)
            }

            if !supporting.isEmpty {
                HStack(spacing: AstraSpacing.md) {
                    ForEach(supporting) { garment in
                        garmentTile(garment, height: AstraSize.lookSupportingHeight)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Today's look", comment: "Accessibility label for the Home outfit"))
        .accessibilityIdentifier("home.look")
    }

    /// The garment the outfit is *about*.
    ///
    /// Top first, then outerwear, then whatever came first from the scorer.
    /// Never the shoes: an outfit led by its shoes is a shoe advert, and the
    /// question this screen answers is what to wear, not what to put on last.
    private var anchor: LookGarment? {
        garments.first { $0.role == .top }
            ?? garments.first { $0.role == .outerwear }
            ?? garments.first
    }

    private var supporting: [LookGarment] {
        guard let anchor else { return [] }
        // Capped at three. A four-piece row on a 320pt phone gives each
        // garment less width than the tap target minimum, and an outfit that
        // needs more than four things shown at once is not a look, it is an
        // inventory — the detail screen is where the full list belongs.
        return garments.filter { $0.id != anchor.id }.prefix(3).map { $0 }
    }

    private func garmentTile(_ garment: LookGarment, height: CGFloat) -> some View {
        Button {
            onTapGarment(garment)
        } label: {
            AstraRemoteImage(
                url: garment.imageURL,
                aspectRatio: 1,
                thumbnail: .closetGridTile,
                accessibilityDescription: garment.item.name
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            // No card, no border, no fill. The cut-outs sit directly on the
            // page the way clothes sit on a bed; a chrome rectangle around
            // each one turns a look back into a list of products.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(garment.item.name))
        .accessibilityHint(Text(String(
            localized: "Opens this piece in your closet",
            comment: "VoiceOver hint for a garment in today's look"
        )))
    }
}
