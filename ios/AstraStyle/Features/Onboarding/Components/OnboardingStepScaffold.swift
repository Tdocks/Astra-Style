//
//  OnboardingStepScaffold.swift
//  AstraStyle
//
//  Shared chrome for every §6.3–§6.10 step: progress, title, rationale,
//  scrolling content, and the back/forward controls.
//
//  Extracted rather than repeated because the alternative is eight screens that
//  drift apart — one with a slightly different title size, another whose
//  Continue button sits a few points higher. On a flow a user sees once, in
//  sequence, that inconsistency is the thing that makes it feel unfinished.
//

import SwiftUI

struct OnboardingStepScaffold<Content: View>: View {
    let step: OnboardingStep
    let advanceTitle: String
    let canAdvance: Bool
    let canGoBack: Bool
    let onAdvance: () -> Void
    let onBack: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                content()
                    .padding(.horizontal, AstraSpacing.pagePadding)
                    .padding(.top, AstraSpacing.lg)
                    // Bottom padding clears the pinned footer. Without it the
                    // last option in a long list sits underneath the Continue
                    // button and cannot be tapped — which at the largest
                    // Dynamic Type sizes is most of them.
                    .padding(.bottom, AstraSpacing.xxxl)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            if let position = step.answerablePosition {
                HStack(spacing: AstraSpacing.sm) {
                    ProgressView(
                        value: Double(position),
                        total: Double(OnboardingStep.answerableSteps.count)
                    )
                    .tint(AstraColor.accentChampagne)
                    .accessibilityLabel(
                        String(
                            format: String(localized: "Step %d of %d",
                                           comment: "Onboarding progress, VoiceOver"),
                            position, OnboardingStep.answerableSteps.count
                        )
                    )

                    Text("\(position)/\(OnboardingStep.answerableSteps.count)")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                        .monospacedDigit()
                        // The bar already conveys this to VoiceOver; repeating
                        // it would read the position out twice.
                        .accessibilityHidden(true)
                }
            }

            Text(step.title)
                .astraText(.title1)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(step.rationale)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
        .padding(.top, AstraSpacing.md)
    }

    private var footer: some View {
        VStack(spacing: AstraSpacing.sm) {
            Divider().overlay(AstraColor.divider)

            // Stacks vertically at accessibility sizes rather than squeezing two
            // buttons onto one line, where the labels truncate to "Bac..." and
            // "Contin...".
            let stackVertically = typeSize >= .accessibility1

            if stackVertically {
                VStack(spacing: AstraSpacing.sm) {
                    advanceButton
                    if canGoBack { backButton }
                }
            } else {
                HStack(spacing: AstraSpacing.sm) {
                    if canGoBack { backButton }
                    advanceButton
                }
            }
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
        .padding(.bottom, AstraSpacing.md)
        .background(AstraColor.backgroundPrimary)
    }

    private var advanceButton: some View {
        AstraButton(title: advanceTitle, action: onAdvance)
            .disabled(!canAdvance)
            .accessibilityIdentifier("onboarding.advance")
    }

    // `AstraButton` is primary-only by design (see its doc comment: most call
    // sites should reach for the style directly). Back is tertiary, so it uses
    // the style rather than the convenience wrapper.
    private var backButton: some View {
        Button(String(localized: "Back", comment: "Onboarding back button"), action: onBack)
            .buttonStyle(.astraTertiary)
            .accessibilityIdentifier("onboarding.back")
    }
}
