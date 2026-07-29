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
//  WHERE THIS GEOMETRY CAME FROM
//
//  Not from eyeballing the logo. Five hand-fitted attempts all missed, because
//  the mark has structure that is genuinely hard to see by looking:
//
//    • It is not a letter "A". It is an open chevron with no crossbar and no
//      closed bottom — the legs simply end in broad, angled feet.
//    • The swoosh CUTS THROUGH the right leg. That leg is not one stroke; the
//      swoosh severs it, leaving the lower portion as a separate closed shape.
//      Every hand-drawn attempt rendered the leg continuous, and that single
//      difference is most of why they read as "close but wrong".
//    • The swoosh tapers asymmetrically and its arc sags toward the
//      bottom-left before rising to a fine point beneath the star.
//
//  So the paths below were TRACED from the master app-icon artwork
//  (brand/assets/app-icon-marble.jpg): the gold mark was isolated by colour,
//  cleaned, and vectorised, then normalised to a 0–100 grid. The result was
//  rendered back beside the original and confirmed identical.
//
//  Consequently: do NOT hand-edit the coordinates. If the brand mark changes,
//  re-trace from the new artwork. Nudging control points here will silently
//  drift the logo away from the brand asset, which is exactly the failure this
//  file exists to prevent.
//

import SwiftUI

/// The Astra "A": an open chevron cut by a rising swoosh, with the star that
/// gives the brand its name.
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
        AstraMonogramShape()
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true) // Decorative; the wordmark carries the name.
    }
}

// MARK: - Shape

/// Renders all three traced subpaths into a single `Path`.
///
/// They are filled as one shape rather than three stacked views so the mark
/// composites once — relevant on the splash screen, where this is drawn before
/// anything else is ready.
struct AstraMonogramShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Square and centred, so a non-square frame does not distort the mark.
        let side = min(rect.width, rect.height)
        let origin = CGPoint(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2
        )

        var path = Path()
        for contour in AstraMonogramGeometry.all {
            AstraMonogramGeometry.append(contour, to: &path, side: side, origin: origin)
        }
        return path
    }
}

// MARK: - Traced geometry

/// Vector data traced from the master brand artwork, on a 0–100 grid.
///
/// Stored as FLAT `[CGFloat]` arrays rather than an array of enum cases or
/// `CGPoint`s. That is not a style choice: an array literal of ~100 enum cases
/// carrying CGPoints made the Swift type checker give up outright ("unable to
/// type-check this expression in reasonable time"). A homogeneous array of
/// numeric literals checks instantly.
///
/// Layout: `[startX, startY, c1x, c1y, c2x, c2y, x, y, c1x, c1y, ...]` — two
/// leading values for the start point, then six per cubic segment. Every
/// segment is a curve; the trace produced no corner points on these contours.
enum AstraMonogramGeometry {
    static var all: [[CGFloat]] { [letterform, rightLegLower, star] }

    /// `letterform` — start point followed by 67 cubic segments.
    static let letterform: [CGFloat] = [
        13, 99.84, 13.3, 99.65, 15.23, 97.59, 17.29, 95.27, 22.21, 89.73, 31.13, 80.34,
        35.28, 76.34, 37.09, 74.58, 40.57, 71.2, 43, 68.83, 47.79, 64.15, 49.69, 62.41,
        53.17, 59.56, 54.41, 58.55, 56.16, 57.06, 57.08, 56.26, 59.88, 53.82, 65.45,
        49.42, 67.62, 47.94, 67.87, 47.77, 68.66, 47.22, 69.38, 46.72, 70.09, 46.22,
        71.42, 45.32, 72.33, 44.72, 76.01, 42.3, 76.8, 41.39, 74.97, 41.66, 73.25,
        41.92, 64.73, 46.27, 59.05, 49.8, 57.98, 50.46, 56.41, 51.4, 55.58, 51.87,
        52.77, 53.47, 42.74, 60.72, 37.96, 64.62, 34.14, 67.73, 19.19, 82.35, 17.69,
        84.44, 16.81, 85.67, 15.94, 86.19, 15.5, 85.75, 15.24, 85.49, 15.69, 84.48,
        18.97, 77.96, 21.04, 73.84, 23.06, 69.77, 23.46, 68.93, 24.27, 67.23, 31.06,
        53.87, 32.61, 50.93, 33.15, 49.91, 34.57, 47.13, 35.76, 44.75, 36.95, 42.38,
        38.27, 39.83, 38.7, 39.09, 39.12, 38.36, 39.81, 36.97, 40.22, 36.01, 40.64,
        35.05, 41.12, 33.98, 41.3, 33.64, 41.47, 33.3, 42.47, 31.36, 43.52, 29.32,
        44.57, 27.28, 46.06, 24.46, 46.84, 23.05, 47.62, 21.63, 48.6, 19.77, 49.02,
        18.91, 49.82, 17.26, 50.19, 16.81, 50.54, 17.04, 50.81, 17.21, 53.67, 22.76,
        54.65, 25, 55.04, 25.91, 55.54, 27.02, 55.74, 27.47, 56.97, 30.14, 57.2, 30.69,
        57.2, 30.92, 57.2, 31.05, 57.43, 31.63, 57.7, 32.2, 58.47, 33.78, 60.7, 38.81,
        60.7, 38.96, 60.7, 39.03, 61.2, 40.16, 61.82, 41.46, 63.07, 44.11, 63.48, 44.38,
        64.75, 43.36, 65.63, 42.65, 66.95, 41.83, 67.77, 41.49, 68.88, 41.02, 68.89,
        40.55, 67.81, 37.8, 67.29, 36.48, 66.87, 35.29, 66.87, 35.16, 66.87, 35.03,
        66.7, 34.64, 66.48, 34.28, 66.27, 33.93, 66.03, 33.41, 65.95, 33.13, 65.87,
        32.84, 65.46, 31.87, 65.02, 30.97, 64.59, 30.06, 63.85, 28.49, 63.37, 27.47,
        62.9, 26.45, 62.15, 24.86, 61.7, 23.93, 60.73, 21.89, 59.74, 19.54, 59.38,
        18.39, 59.23, 17.92, 58.96, 17.32, 58.77, 17.05, 58.59, 16.79, 58.44, 16.43,
        58.44, 16.26, 58.44, 16.09, 58.21, 15.49, 57.94, 14.92, 56.57, 12.07, 55.47,
        9.69, 54.23, 6.89, 53.48, 5.2, 52.63, 3.32, 52.36, 2.72, 52.08, 2.13, 51.85,
        1.51, 51.85, 1.36, 51.85, 0.4, 50.38, -0.35, 49.98, 0.41, 49.9, 0.58, 49.3,
        1.83, 48.65, 3.19, 48.01, 4.55, 46.83, 6.95, 46.04, 8.54, 45.25, 10.12, 43.49,
        13.63, 42.14, 16.33, 40.79, 19.03, 39.28, 21.91, 38.78, 22.74, 38.28, 23.56,
        37.55, 24.96, 37.16, 25.85, 36.49, 27.34, 34.14, 32.04, 32.85, 34.44, 32.55, 35,
        32.3, 35.59, 32.3, 35.76, 32.3, 35.94, 31.79, 37.05, 31.15, 38.24, 30.52, 39.42,
        29.48, 41.38, 28.86, 42.57, 28.23, 43.77, 27.4, 45.35, 27.01, 46.09, 26.62,
        46.83, 25.44, 49.33, 24.37, 51.65, 23.31, 53.97, 21.6, 57.44, 20.58, 59.36,
        19.56, 61.29, 17.14, 66.05, 15.2, 69.96, 13.25, 73.86, 11.01, 78.26, 10.2,
        79.73, 9.39, 81.2, 7.13, 85.6, 5.17, 89.51, 3.21, 93.41, 1.24, 97.23, 0.79, 98,
        -0.42, 100.04, -0.57, 99.98, 5.53, 100.05, 8.32, 100.08, 11.01, 100.13, 11.52,
        100.16, 12.12, 100.19, 12.64, 100.08, 13, 99.84
    ]

    /// `rightLegLower` — start point followed by 31 cubic segments.
    static let rightLegLower: [CGFloat] = [
        94.91, 100.02, 95.22, 99.98, 95.05, 98.93, 94.57, 97.99, 94.3, 97.45, 94.02,
        96.71, 93.94, 96.33, 93.8, 95.69, 92.39, 92.4, 91.24, 90.02, 90.97, 89.45,
        90.74, 88.92, 90.74, 88.83, 90.74, 88.74, 90.29, 87.73, 89.74, 86.57, 88.75,
        84.49, 87.58, 81.87, 85.3, 76.65, 84.66, 75.17, 83.96, 73.6, 83.75, 73.15,
        83.53, 72.7, 83.07, 71.68, 82.72, 70.88, 82.36, 70.09, 81.9, 69.07, 81.69,
        68.62, 81.47, 68.17, 81.01, 67.1, 80.65, 66.26, 80.3, 65.41, 79.79, 64.25,
        79.52, 63.68, 77.34, 59.08, 76.14, 56.42, 75.8, 55.45, 75.09, 53.42, 72.8,
        48.96, 72.3, 48.63, 71.9, 48.37, 71.79, 48.41, 70.86, 49.24, 70.31, 49.74,
        69.28, 50.53, 68.57, 51.01, 67.11, 52.01, 66.96, 52.48, 67.7, 53.91, 67.92,
        54.35, 68.11, 54.83, 68.11, 54.98, 68.11, 55.12, 68.33, 55.71, 68.61, 56.27,
        68.89, 56.84, 69.4, 58, 69.75, 58.85, 70.83, 61.46, 71.4, 62.76, 72.58, 65.33,
        74.37, 69.23, 74.43, 69.35, 75.21, 71.19, 75.61, 72.16, 76.12, 73.31, 76.33,
        73.77, 76.55, 74.22, 77.02, 75.24, 77.37, 76.03, 77.73, 76.82, 78.28, 78.02,
        78.59, 78.7, 78.91, 79.38, 79.41, 80.49, 79.72, 81.17, 80.03, 81.85, 80.45,
        82.78, 80.66, 83.23, 80.87, 83.68, 81.84, 85.86, 82.82, 88.07, 83.79, 90.27,
        84.77, 92.45, 84.99, 92.9, 85.58, 94.14, 86.63, 96.65, 86.63, 96.83, 86.63,
        97.12, 87.87, 99.55, 88.13, 99.76, 88.47, 100.04, 93.21, 100.22, 94.91, 100.02
    ]

    /// `star` — start point followed by 4 cubic segments.
    static let star: [CGFloat] = [
        90.23, 39, 95.4, 35.97, 95.25, 29.1, 89.96, 26.5, 85.14, 24.12, 79.87, 27.58,
        80.08, 32.98, 80.17, 35.49, 80.61, 36.41, 82.48, 38.08, 84.48, 39.86, 88.04,
        40.29, 90.23, 39
    ]

    /// Appends one flat contour to `path`, scaled onto `side` points.
    static func append(_ contour: [CGFloat], to path: inout Path, side: CGFloat, origin: CGPoint) {
        guard contour.count >= 8, (contour.count - 2) % 6 == 0 else {
            assertionFailure("Malformed contour: expected 2 + 6n values, got \(contour.count)")
            return
        }

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x / 100 * side,
                    y: origin.y + y / 100 * side)
        }

        path.move(to: point(contour[0], contour[1]))
        var i = 2
        while i + 5 < contour.count {
            path.addCurve(
                to: point(contour[i + 4], contour[i + 5]),
                control1: point(contour[i], contour[i + 1]),
                control2: point(contour[i + 2], contour[i + 3])
            )
            i += 6
        }
        path.closeSubpath()
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
