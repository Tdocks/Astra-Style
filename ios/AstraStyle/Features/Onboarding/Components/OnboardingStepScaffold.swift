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
            // Only the progress bar is pinned. The title and rationale scroll
            // WITH the content, and that is load-bearing rather than cosmetic:
            // when they were part of a fixed header, an accessibility-size run
            // left roughly a 60pt sliver of usable content between a 450pt
            // header and a 150pt footer — the first identity card rendered as
            // "Moder…" and nothing below it could be reached at all. A fixed
            // header is only safe when its height is bounded, and text that
            // scales with Dynamic Type is not.
            progressBar
                .padding(.horizontal, AstraSpacing.pagePadding)
                .padding(.top, AstraSpacing.md)
                .padding(.bottom, AstraSpacing.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                    titleBlock
                    content()
                }
                .padding(.horizontal, AstraSpacing.pagePadding)
                // Clears the pinned footer. Without it the last option in a long
                // list sits underneath the Continue button and cannot be tapped.
                .padding(.bottom, AstraSpacing.xxxl)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
    }

    private var progressBar: some View {
        Group {
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
                        // The bar already conveys this to VoiceOver; repeating it
                        // would read the position out twice.
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(step.title)
                .astraText(.title1)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(step.rationale)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
