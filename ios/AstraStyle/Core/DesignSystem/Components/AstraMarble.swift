//
//  AstraMarble.swift
//  AstraStyle
//
//  The black-marble brand texture, generated rather than shipped as an image.
//
//  Spec §3 is emphatic that marble is a brand texture, NOT a universal
//  background. It belongs on exactly five surfaces:
//
//      • the splash screen
//      • the app icon
//      • the paywall hero
//      • select premium cards
//      • Kyra transition surfaces
//
//  and explicitly never behind dense text.
//
//  Drawing it with layered gradients instead of a bundled photograph keeps the
//  app binary small, scales to any device without a 3x asset set, and lets the
//  veining tint with the palette. `AstraColor.surfaceMarble` currently degrades
//  to `backgroundPrimary`; this view is the real treatment that token
//  described.
//

import SwiftUI

/// The Astra marble texture: near-black stone with faint champagne-warm veining.
///
/// Use `.astraMarbleBackground()` rather than placing this by hand, so the
/// safe-area and layering behaviour stays consistent.
public struct AstraMarble: View {
    /// How pronounced the veining is. Kept low by default — the texture should
    /// register as material, not pattern.
    private let intensity: Double

    public init(intensity: Double = 1.0) {
        self.intensity = max(0, min(intensity, 1.5))
    }

    public var body: some View {
        ZStack {
            // Base stone. Not flat black: a slight vertical gradient is what
            // separates "stone" from "the screen is off".
            LinearGradient(
                colors: [
                    Color(hex: "#121212"),
                    Color(hex: "#070707"),
                    Color(hex: "#0C0C0C")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Broad tonal drifts — the cloudiness within the stone.
            ForEach(Array(Self.drifts.enumerated()), id: \.offset) { _, drift in
                RadialGradient(
                    colors: [
                        Color(hex: "#8A8880").opacity(drift.opacity * intensity),
                        .clear
                    ],
                    center: drift.center,
                    startRadius: 0,
                    endRadius: drift.radius
                )
            }

            // Veins. Thin, angled, and few — marble reads expensive because the
            // veining is sparse and confident, not busy.
            Canvas { context, size in
                for vein in Self.veins {
                    var path = Path()
                    path.move(to: CGPoint(x: vein.start.x * size.width,
                                          y: vein.start.y * size.height))
                    path.addQuadCurve(
                        to: CGPoint(x: vein.end.x * size.width,
                                    y: vein.end.y * size.height),
                        control: CGPoint(x: vein.control.x * size.width,
                                         y: vein.control.y * size.height)
                    )
                    context.stroke(
                        path,
                        with: .color(Color(hex: "#C9C4B8").opacity(vein.opacity * intensity)),
                        lineWidth: vein.width
                    )
                }
            }
            .blur(radius: 1.4) // Softer: veining should sit inside the stone, not on top of it.
        }
        .drawingGroup() // Flatten the stack once rather than compositing every frame.
    }

    // MARK: - Texture definition
    //
    // Fixed rather than random: the mark must look identical on every launch
    // and every device. A randomised texture would also break snapshot tests.

    private struct Drift {
        let center: UnitPoint
        let radius: CGFloat
        let opacity: Double
    }

    private struct Vein {
        let start: UnitPoint
        let control: UnitPoint
        let end: UnitPoint
        let width: CGFloat
        let opacity: Double
    }

    private static let drifts: [Drift] = [
        Drift(center: UnitPoint(x: 0.20, y: 0.15), radius: 420, opacity: 0.13),
        Drift(center: UnitPoint(x: 0.78, y: 0.65), radius: 360, opacity: 0.10),
        Drift(center: UnitPoint(x: 0.55, y: 0.92), radius: 300, opacity: 0.08)
    ]

    // Short, low-contrast, and steeply curved. The first pass used long veins
    // running most of the screen's height at ~0.16 opacity, and they read as
    // scratches on glass rather than mineral in stone — the giveaway was that
    // they were nearly straight. Real veining changes direction over a short
    // run, so these use tight control points and stop well short of the edges.
    private static let veins: [Vein] = [
        Vein(start: UnitPoint(x: 0.02, y: 0.34), control: UnitPoint(x: 0.20, y: 0.12),
             end: UnitPoint(x: 0.46, y: 0.17), width: 0.9, opacity: 0.085),
        Vein(start: UnitPoint(x: 0.40, y: 0.14), control: UnitPoint(x: 0.62, y: 0.21),
             end: UnitPoint(x: 0.74, y: 0.06), width: 0.6, opacity: 0.06),
        Vein(start: UnitPoint(x: 0.16, y: 0.94), control: UnitPoint(x: 0.34, y: 0.74),
             end: UnitPoint(x: 0.58, y: 0.79), width: 0.75, opacity: 0.07),
        Vein(start: UnitPoint(x: 0.80, y: 0.52), control: UnitPoint(x: 0.92, y: 0.66),
             end: UnitPoint(x: 0.86, y: 0.84), width: 0.55, opacity: 0.05)
    ]
}

public extension View {
    /// Places the marble texture behind this view, extending under the safe area.
    ///
    /// Reserve this for the surfaces spec §3 names. If you are reaching for it
    /// behind body copy, the answer is `AstraColor.backgroundPrimary`.
    ///
    /// - Parameter scrimmed: Adds a bottom-weighted scrim so foreground content
    ///   stays legible over the brighter parts of the stone. Default `true`.
    func astraMarbleBackground(scrimmed: Bool = true) -> some View {
        background {
            ZStack {
                AstraMarble()
                if scrimmed {
                    LinearGradient(
                        colors: [
                            AstraColor.backgroundPrimary.opacity(0.10),
                            AstraColor.backgroundPrimary.opacity(0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .ignoresSafeArea()
        }
    }
}

#Preview("Marble") {
    ZStack {
        Color.clear.astraMarbleBackground()
        AstraMonogram(size: 96)
    }
}
