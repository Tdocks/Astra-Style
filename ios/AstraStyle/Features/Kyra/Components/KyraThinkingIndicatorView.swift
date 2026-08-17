//
//  KyraThinkingIndicatorView.swift
//  AstraStyle
//
//  The in-flight row while Kyra composes a reply: her mark, breathing.
//  Spec §3's motion table gives the Kyra orb exactly one behaviour —
//  "subtle breathing animation, never distracting" — and this is its
//  implementation: a slow scale oscillation on `AstraMotion.breathing`
//  (2.4 s ease-in-out), no spinners, no typing dots. Reduce Motion stills
//  it entirely; the accompanying sentence carries the state on its own,
//  which is also what VoiceOver reads.
//

import SwiftUI

struct KyraThinkingIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        HStack(spacing: AstraSpacing.sm) {
            AstraMonogram(size: AstraSpacing.xl)
                .scaleEffect(isBreathing ? 1.08 : 1.0)
                .accessibilityHidden(true)
            Text(String(localized: "Kyra is thinking…", comment: "Shown while a Kyra reply is in flight"))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(AstraMotion.breathing.repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("kyra.thinking")
    }
}
