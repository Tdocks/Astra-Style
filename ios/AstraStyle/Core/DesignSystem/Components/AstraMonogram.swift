//
//  AstraMonogram.swift
//  AstraStyle
//
//  The Astra "A" mark, drawn as a vector rather than shipped as a raster.
//
//  Spec §3 lists the logo wordmark as "a separate vector asset". Drawing the
//  monogram as a `Shape` keeps it crisp at every size and Dynamic Type
//  setting, tints with the current style rather than needing one asset per
//  colour scheme, and avoids a launch-path dependency on the asset catalog —
//  which matters because this mark appears on the splash, before most of the
//  app has initialised.
//
//  GEOMETRY
//
//  Coordinates were measured off the brand reference (brand/assets/
//  logo-wordmark-light.jpg) rather than eyeballed, normalised to a 100×100
//  box with the letterform inset to leave room for the star.
//
//  The mark is NOT a solid letter "A". It is a hollow chevron:
//
//    • two tapering legs meeting at a sharp apex
//    • an open counter between them — you see through the middle
//    • NO crossbar and NO closed bottom; the legs simply end in flat feet
//
//  A first attempt drew a solid triangle with a notch cut out, which read as a
//  generic letter A with a slash through it. The openness is the whole
//  identity: it is a chevron and a rising path, not a letterform with
//  decoration applied.
//

import SwiftUI

/// The Astra "A": an open chevron, a rising swoosh, and the star that gives
/// the brand its name.
public struct AstraMonogram: View {
    private let size: CGFloat
    private let tint: Color

    /// - Parameters:
    ///   - size: Width and height of the mark's square bounding box.
    ///   - tint: Mark colour. Defaults to champagne, the brand's active state.
    public init(size: CGFloat = 64, tint: Color = AstraColor.accentChampagne) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            AstraChevronShape()
            AstraSwooshShape()
            AstraStarShape()
        }
        .foregroundStyle(tint)
        .frame(width: size, height: size)
        .accessibilityHidden(true) // Decorative; the wordmark carries the name.
    }
}

// MARK: - Normalised coordinate helper

/// Maps the measured 0–100 design grid onto whatever rect the shape is given.
private func gridPoint(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    let side = min(rect.width, rect.height)
    return CGPoint(x: rect.minX + x / 100 * side,
                   y: rect.minY + y / 100 * side)
}

// MARK: - Component shapes

/// The hollow chevron.
///
/// Traced as ONE closed polygon rather than two separate legs, so the counter
/// between them falls out of the winding instead of needing an even-odd fill:
/// apex → down the right outer edge → across the right foot → back up the
/// right inner edge to the inner apex → down the left inner edge → across the
/// left foot → up the left outer edge and closed.
private struct AstraChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { gridPoint(x, y, in: rect) }

        var path = Path()
        path.move(to: p(52, 5))      // outer apex — the sharp tip
        path.addLine(to: p(97, 95))  // right leg, outer edge
        path.addLine(to: p(88, 95))  // right foot, flat
        path.addLine(to: p(52, 15))  // back up the inner edge to the inner apex
        path.addLine(to: p(13, 95))  // down the left leg's inner edge
        path.addLine(to: p(3, 95))   // left foot, flat
        path.closeSubpath()          // up the left outer edge to the apex
        return path
    }
}

/// The rising swoosh: a long crescent from the base of the left leg, sweeping
/// up across the right leg and past it, tapering to a point beneath the star.
///
/// Built as two curves with different control points rather than a stroked
/// line. That mismatch is what produces the taper — fine at both tips, fullest
/// through the middle. A uniform stroke reads as a scratch across the mark
/// rather than a gesture, and the taper is most of why the logo feels drawn
/// rather than constructed.
///
/// Both control points sit BELOW the chord between the tips, so the arc sags
/// toward the bottom-left before rising. Earlier attempts put them left of the
/// chord instead, which made the swoosh bulge sideways and hook — the
/// difference between a sweep and a fishhook is entirely in which side of the
/// chord the control points fall on.
private struct AstraSwooshShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { gridPoint(x, y, in: rect) }

        var path = Path()
        path.move(to: p(16, 82))                                   // lower-left tip
        path.addQuadCurve(to: p(79, 44), control: p(47, 76))       // upper edge
        path.addQuadCurve(to: p(16, 82), control: p(52, 83))       // lower edge, back
        path.closeSubpath()
        return path
    }
}

/// The star (astra) sitting off the swoosh's tip, clear of the right leg.
private struct AstraStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = gridPoint(84, 35, in: rect)
        let radius = 6.0 / 100 * side
        return Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }
}

// MARK: - Wordmark

/// "ASTRA" over a ruled "STYLE", matching the brand lockup.
///
/// Tracking and the champagne rules are part of the mark, not decoration —
/// setting the wordmark without them reads as a generic serif heading.
public struct AstraWordmark: View {
    private let showsTagline: Bool

    public init(showsTagline: Bool = false) {
        self.showsTagline = showsTagline
    }

    public var body: some View {
        VStack(spacing: AstraSpacing.xs) {
            Text("ASTRA")
                .astraText(.displayL)
                .tracking(10)
                // Tracking adds trailing space after the final letter, which
                // visually shifts the word left of centre. Offsetting by the
                // tracking value re-centres it under the mark.
                .padding(.leading, 10)
                .foregroundStyle(AstraColor.textPrimary)

            HStack(spacing: AstraSpacing.xs) {
                rule
                Text("STYLE")
                    .astraText(.micro)
                    .tracking(6)
                    .padding(.leading, 6)
                    .foregroundStyle(AstraColor.textPrimary)
                rule
            }

            if showsTagline {
                Text("Your style. Your journey. Your best self.")
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, AstraSpacing.sm)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Astra Style"))
    }

    private var rule: some View {
        Rectangle()
            .fill(AstraColor.accentChampagne)
            .frame(width: 28, height: 1)
    }
}

#Preview("Monogram & wordmark") {
    ZStack {
        AstraColor.backgroundPrimary.ignoresSafeArea()
        VStack(spacing: AstraSpacing.xxl) {
            AstraMonogram(size: 120)
            AstraWordmark(showsTagline: true)
        }
    }
}
