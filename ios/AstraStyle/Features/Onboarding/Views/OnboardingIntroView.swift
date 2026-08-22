//
//  OnboardingIntroView.swift
//  AstraStyle
//
//  Spec §6.3 — Kyra introduction.
//
//  Kyra's mark is `AstraMonogram`. The glyph vocabulary every AI product
//  reaches for — wands, stars, and the four-pointed twinkle — is banned
//  outright (docs/07 §2, enforced by scripts/check_ui_conventions.py): §3's
//  visual principle is that the technology stays invisible, and a wand is the
//  technology waving. §6.3 also specifies "an elegant abstract portrait, not
//  photorealistic human deception" — so no face, and nothing implying Kyra is
//  a person.
//

import SwiftUI

struct OnboardingIntroView: View {
    let onBegin: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color.clear.astraMarbleBackground()

            VStack(spacing: AstraSpacing.xl) {
                Spacer()

                AstraMonogram(size: 96)
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.94)

                VStack(spacing: AstraSpacing.md) {
                    Text("I'm Kyra.")
                        .astraText(.displayL)
                        .foregroundStyle(AstraColor.textPrimary)

                    // Spec §6.3's copy, verbatim. It is the first thing the
                    // product says in its own voice and is not paraphrased.
                    Text("I'll learn your wardrobe, your preferences, and the way you live — then help you dress with intention.")
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(hasAppeared ? 1 : 0)

                Spacer()

                VStack(spacing: AstraSpacing.sm) {
                    AstraButton(
                        title: String(localized: "Let's begin", comment: "Onboarding intro primary action"),
                        action: onBegin
                    )
                    .accessibilityIdentifier("onboarding.begin")

                    // Sets the expectation before the questions start. A user who
                    // knows the length and knows he can skip is far likelier to
                    // finish than one who discovers both halfway through.
                    Text("\(OnboardingStep.answerableSteps.count) short steps. How you want to look is required — skip the rest.")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        // Marble is black stone in both colour schemes, so anything drawn on it
        // is on a dark surface regardless of the user's theme.
        .astraOnMarble()
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(AstraMotion.aware(AstraMotion.standard, reduceMotion: reduceMotion)) {
                hasAppeared = true
            }
        }
    }
}

#Preview("Intro") {
    OnboardingIntroView(onBegin: {})
}
