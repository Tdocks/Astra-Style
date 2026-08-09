//
//  LookSilhouetteView.swift
//  AstraStyle
//
//  An outfit laid out the way it would be worn: top over bottom over shoes,
//  proportioned to the wearer's own frame. The point is that a look can be
//  judged at a glance — "too dressy for a Tuesday" is a reaction to a
//  SHAPE, and a list of four product photographs does not have one.
//
//  IT IS THE USER'S ACTUAL CLOTHES, AND THAT IS THE DESIGN DECISION.
//  The obvious alternative was to generate a photograph of a model of
//  similar build wearing lookalike garments. It would be handsomer. It
//  would also cost a generation per look, take seconds per look, and — the
//  part that rules it out — show garments that are not the ones in his
//  closet. A man deciding "yes, that" from a rendered approximation and
//  then pulling the real shirt out of the wardrobe has been sold something
//  Astra cannot deliver, which is the confounded reading this codebase
//  keeps refusing. Every garment here is a cut-out of a photograph he took.
//
//  WHAT THE FRAME DOES AND DOES NOT DO.
//  `FrameProfile` sets the PROPORTIONS of the slots — how much of the
//  height is torso, how much is leg, how much narrower the hips read than
//  the shoulders. It does not draw a body, and there is no human figure
//  behind the clothes. That is deliberate: a rendered body is a claim about
//  what the user looks like, and spec §2 rules out exactly that kind of
//  claim. Proportion is the honest half of the idea — it is derived from
//  measurements he gave, and it is invisible as anything but "this looks
//  like it would sit on me".
//
//  AND WHEN THE FRAME IS UNKNOWN, NOTHING IS CLAIMED.
//  Every axis of `FrameProfile` is optional and most users will have none
//  of them (spec §6.6 allows "I don't know" on every field). An unknown
//  axis falls back to the balanced value, which is what the layout used
//  before frames existed. A LOW-CONFIDENCE axis does the same: a taper
//  derived at 0.2 confidence is a guess, and reshaping a man's outfit
//  preview around a guess is how an app starts feeling like it is
//  describing someone else.
//

import SwiftUI

struct LookSilhouetteView: View {
    let garments: [LookGarment]
    var frame: FrameProfile = .unknown
    var height: CGFloat = AstraSize.silhouetteHeight
    var onTapGarment: ((LookGarment) -> Void)?

    /// Below this, an axis is treated as unknown. `FrameDerivation` assigns
    /// confidence from how many measurements the user actually supplied, so
    /// this is the line between "derived from what he told us" and "derived
    /// from height alone".
    private static let confidenceFloor = 0.4

    var body: some View {
        VStack(spacing: 0) {
            slot(for: topGarment, height: height * layout.torso, widthFactor: 1)
            slot(for: bottomGarment, height: height * layout.leg, widthFactor: layout.hipWidth)
            slot(for: shoesGarment, height: height * Layout.shoes, widthFactor: 0.5)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilitySummary))
        .accessibilityIdentifier("look.silhouette")
    }

    // MARK: - Slots

    /// Outerwear wins the top slot when there is one — it is the layer that
    /// is actually seen, and on a cold day it is the decision the rest of
    /// the outfit was built under.
    private var topGarment: LookGarment? {
        garments.first { $0.role == .outerwear } ?? garments.first { $0.role == .top }
    }

    private var bottomGarment: LookGarment? {
        garments.first { $0.role == .bottom }
    }

    private var shoesGarment: LookGarment? {
        garments.first { $0.role == .shoes }
    }

    /// An empty slot is empty. It is not a placeholder, a dashed outline or
    /// a "+ add trousers" — an outfit that reached this screen without a
    /// bottom half is a scoring failure, and drawing a suggestion box over
    /// the gap would hide it.
    @ViewBuilder
    private func slot(for garment: LookGarment?, height slotHeight: CGFloat, widthFactor: CGFloat) -> some View {
        if let garment {
            Button {
                onTapGarment?(garment)
            } label: {
                AstraRemoteImage(
                    url: garment.imageURL,
                    aspectRatio: 1,
                    thumbnail: .closetGridTile,
                    showsBackground: false,
                    contentMode: .fit,
                    accessibilityDescription: garment.item.name
                )
                .frame(height: slotHeight)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: widthFactor, anchor: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onTapGarment == nil)
            .accessibilityLabel(Text(garment.item.name))
        } else {
            Color.clear.frame(height: slotHeight)
        }
    }

    // MARK: - Proportion

    private struct Layout {
        /// Shoes are a fixed slice. Feet are the one part of a body whose
        /// proportion does not meaningfully vary with build.
        static let shoes: CGFloat = 0.14

        var torso: CGFloat
        var leg: CGFloat
        var hipWidth: CGFloat
    }

    private var layout: Layout {
        let torso: CGFloat = switch confident(frame.proportion)?.value {
        case .longTorso: 0.50
        case .longLeg: 0.38
        case .balanced, nil: 0.44
        }

        let hipWidth: CGFloat = switch confident(frame.taper)?.value {
        case .strong: 0.74
        case .straight: 0.92
        case .moderate, nil: 0.84
        }

        return Layout(torso: torso, leg: 1 - Layout.shoes - torso, hipWidth: hipWidth)
    }

    private func confident<Value>(_ axis: FrameAxis<Value>?) -> FrameAxis<Value>? {
        guard let axis, axis.confidence >= Self.confidenceFloor else { return nil }
        return axis
    }

    /// One sentence naming the pieces, because a silhouette read aloud slot
    /// by slot ("image, image, image") tells a VoiceOver user nothing.
    private var accessibilitySummary: String {
        let names = [topGarment, bottomGarment, shoesGarment]
            .compactMap { $0?.item.name }
        guard !names.isEmpty else {
            return String(localized: "An outfit with nothing to show yet",
                          comment: "Accessibility label for an empty silhouette")
        }
        return names.joined(separator: ", ")
    }
}
