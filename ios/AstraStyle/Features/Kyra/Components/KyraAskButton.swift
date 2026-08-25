//
//  KyraAskButton.swift
//  AstraStyle
//
//  The "Ask Kyra" global action (spec §4) as a floating control above the
//  tab bar — the door to the conversation modal, drawn on every tab
//  because a global action that exists on some tabs is a navigation model
//  the user has to memorize.
//
//  IT IS THE MONOGRAM, NOT A WAND. Kyra's mark is `AstraMonogram`
//  (spec §3 "technology remains invisible"; the UI convention check
//  bans the AI-wand glyph by regex), and the orb breathes on
//  `AstraMotion.breathing` per §3's motion table — the same behaviour,
//  and the same Reduce Motion stillness, as the thinking indicator.
//

import SwiftUI

struct KyraAskButton: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    /// Orb diameter: comfortably above the 44 pt floor without dominating
    /// the content it floats over.
    private static let diameter = AstraSize.minTapTarget + AstraSpacing.sm

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AstraColor.surfaceElevated)
                Circle()
                    .strokeBorder(AstraColor.accentChampagne, lineWidth: 1)
                AstraMonogram(size: AstraSpacing.xl + AstraSpacing.xxs)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .scaleEffect(isBreathing ? 1.04 : 1.0)
            .shadow(color: AstraColor.accentChampagne.opacity(0.18), radius: AstraSpacing.sm)
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(AstraMotion.breathing.repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .accessibilityLabel(Text(String(localized: "Ask Kyra", comment: "Opens the Kyra conversation")))
        .accessibilityIdentifier("kyra.ask")
    }
}
