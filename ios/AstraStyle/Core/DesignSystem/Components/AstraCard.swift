//
//  AstraCard.swift
//  AstraStyle
//
//  Elevated surface container (spec §3: 18 pt radius; "Use soft shadows only in light mode. Use
//  subtle 1 px borders in dark mode."). That asymmetry is explicit in the spec — this
//  implementation keeps the two appearances genuinely different rather than averaging them
//  into a single shadow-and-border treatment.
//

import SwiftUI

/// The standard elevated card surface used throughout Astra Style (outfit cards, Wardrobe
/// Score module, Kyra's Insight, etc).
///
/// - Dark mode (the app's default appearance): flat `surfaceElevated` fill plus a subtle
///   1 px `divider`-colored border. No shadow — shadows read poorly against a near-black
///   background and are not part of the dark editorial-notebook aesthetic.
/// - Light mode: flat `surfaceElevated` (white) fill plus a soft drop shadow, no border.
public struct AstraCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let padding: CGFloat
    private let content: Content

    /// - Parameters:
    ///   - padding: Internal padding applied around `content`. Defaults to `AstraSpacing.lg` (20 pt).
    ///   - content: The card's contents.
    public init(padding: CGFloat = AstraSpacing.lg, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .fill(AstraColor.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .strokeBorder(AstraColor.divider, lineWidth: colorScheme == .dark ? 1 : 0)
            )
            .shadow(
                color: colorScheme == .light ? Color.black.opacity(0.12) : .clear,
                radius: colorScheme == .light ? 16 : 0,
                x: 0,
                y: colorScheme == .light ? 8 : 0
            )
    }
}
