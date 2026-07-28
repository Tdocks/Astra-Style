//
//  AstraScoreMeter.swift
//  AstraStyle
//
//  0–100 score display used for compatibility score, Wardrobe Score, and Style Studio
//  confidence (spec §6.11, §6.13, §6.19, §10). Spec §19 requires that meaning is never encoded
//  by color alone, so every tier pairs its color with the numeral itself and a text descriptor.
//

import SwiftUI

/// A 0–100 score tier. Thresholds are not specified by spec §3/§10/§19; they are a design
/// decision (documented in `docs/07-design-system.md`) chosen to give four legible bands.
enum AstraScoreTier {
    case excellent
    case strong
    case fair
    case needsAttention

    init(score: Int) {
        switch score {
        case 85...100: self = .excellent
        case 70..<85: self = .strong
        case 50..<70: self = .fair
        default: self = .needsAttention
        }
    }

    /// The text descriptor that always accompanies the numeral and color for this tier.
    var descriptor: String {
        switch self {
        case .excellent: "Excellent"
        case .strong: "Strong"
        case .fair: "Fair"
        case .needsAttention: "Needs Attention"
        }
    }

    var color: Color {
        switch self {
        case .excellent: AstraColor.successOlive
        case .strong: AstraColor.accentChampagneAccessible
        case .fair: AstraColor.warningAmber
        case .needsAttention: AstraColor.destructive
        }
    }
}

/// A 0–100 score display, used for compatibility score, Wardrobe Score, and Style Studio
/// confidence.
///
/// Per spec §19 ("Do not encode meaning by color alone"), the tier color is always shown
/// alongside the numeric score and a text descriptor (e.g. "72 · Strong"), never as a bare
/// color swatch or ring.
public struct AstraScoreMeter: View {
    /// Presentation size.
    public enum Style {
        /// Small inline form for use inside a card or list row.
        case compact
        /// Large hero form for use as a screen's focal element (e.g. Wardrobe Score module).
        case hero
    }

    /// Diameter of the compact ring.
    private static let compactDiameter: CGFloat = 34
    /// Stroke width of the compact ring.
    private static let compactStrokeWidth: CGFloat = 3
    /// Diameter of the hero ring.
    private static let heroDiameter: CGFloat = 148
    /// Stroke width of the hero ring.
    private static let heroStrokeWidth: CGFloat = 8

    private let score: Int
    private let title: String
    private let style: Style

    /// - Parameters:
    ///   - score: Raw score; clamped to `0...100`.
    ///   - title: What the score measures, e.g. "Compatibility" or "Wardrobe Score".
    ///   - style: `.compact` or `.hero`. Defaults to `.compact`.
    public init(score: Int, title: String, style: Style = .compact) {
        self.score = score
        self.title = title
        self.style = style
    }

    private var clampedScore: Int {
        min(max(score, 0), 100)
    }

    private var tier: AstraScoreTier {
        AstraScoreTier(score: clampedScore)
    }

    private var progress: CGFloat {
        CGFloat(clampedScore) / 100
    }

    public var body: some View {
        Group {
            switch style {
            case .compact: compactBody
            case .hero: heroBody
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title): \(clampedScore) out of 100, \(tier.descriptor)."))
    }

    // MARK: Compact

    private var compactBody: some View {
        HStack(spacing: AstraSpacing.sm) {
            ZStack {
                Circle()
                    .stroke(AstraColor.divider, lineWidth: Self.compactStrokeWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tier.color, style: StrokeStyle(lineWidth: Self.compactStrokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(clampedScore)")
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textPrimary)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: Self.compactDiameter, height: Self.compactDiameter)
            .astraAnimation(AstraMotion.standard, value: progress)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                Text(tier.descriptor)
                    .astraText(.callout)
                    .foregroundStyle(tier.color)
            }
        }
    }

    // MARK: Hero

    private var heroBody: some View {
        VStack(spacing: AstraSpacing.sm) {
            ZStack {
                Circle()
                    .stroke(AstraColor.divider, lineWidth: Self.heroStrokeWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tier.color, style: StrokeStyle(lineWidth: Self.heroStrokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: AstraSpacing.xxs) {
                    Text("\(clampedScore)")
                        .astraText(.displayL)
                        .foregroundStyle(AstraColor.textPrimary)
                    Text("/ 100")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                }
            }
            .frame(width: Self.heroDiameter, height: Self.heroDiameter)
            .astraAnimation(AstraMotion.standard, value: progress)

            Text(title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)

            Text(tier.descriptor)
                .astraText(.callout)
                .foregroundStyle(tier.color)
        }
    }
}
