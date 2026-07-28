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
//  Geometry is normalised to a 100×100 box and scaled to fit, so callers set
//  the size and nothing here needs to change.
//

import SwiftUI

/// The Astra "A": an open triangular letterform, a rising swoosh, and the
/// star that gives the brand its name.
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
            AstraLetterAShape()
            AstraSwooshShape()
            AstraStarShape()
        }
        .foregroundStyle(tint)
        .frame(width: size, height: size)
        .accessibilityHidden(true) // Decorative; the wordmark carries the name.
    }
}

// MARK: - Component shapes

/// The open "A" letterform: a peak, two legs, and the counter cut out of it.
private struct AstraLetterAShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }

        var path = Path()
        path.move(to: p(50, 8))
        path.addLine(to: p(86, 86))
        path.addLine(to: p(74, 86))
        path.addLine(to: p(50, 30))
        path.addLine(to: p(33, 68))
        path.addLine(to: p(50, 45))
        path.addLine(to: p(57, 56))
        path.addLine(to: p(26, 86))
        path.addLine(to: p(14, 86))
        path.closeSubpath()
        return path
    }
}

/// The rising swoosh that cuts across the letterform — the "journey" gesture
/// in the tagline, and what keeps the mark from reading as a plain letter A.
private struct AstraSwooshShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }

        var path = Path()
        // Built as a closed ribbon (outbound curve, then a return curve at a
        // slightly different control point) rather than a stroked line. That
        // difference in control points is what makes the swoosh TAPER — wide
        // where it launches at the lower left, fine as it reaches the star. A
        // uniform stroke reads like a scratch across the letterform; the taper
        // is what makes it read as a gesture.
        path.move(to: p(20, 80))
        path.addCurve(to: p(70, 26), control1: p(34, 66), control2: p(50, 40))
        path.addLine(to: p(72, 32))
        path.addCurve(to: p(27, 82), control1: p(52, 46), control2: p(38, 70))
        path.closeSubpath()
        return path
    }
}

/// The star (astra) at the swoosh's apex.
private struct AstraStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let center = CGPoint(x: rect.minX + 75 * s, y: rect.minY + 25 * s)
        let radius = 8 * s
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
                // visually shifts the word left of centre. Offsetting by half
                // the tracking re-centres it under the mark.
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
            AstraMonogram(size: 96)
            AstraWordmark(showsTagline: true)
        }
    }
}
