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
    /// Whether the forward action is currently a skip rather than a submit.
    ///
    /// Passed explicitly instead of inferred from `advanceTitle`, because
    /// comparing against the literal "Skip for now" breaks the moment the string
    /// is localised — and it would break silently, into the wrong style.
    let advanceIsSkip: Bool
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
            }
            // Keyed by step, so each one gets a FRESH scroll view starting at the
            // top. Without this the scaffold is one long-lived ScrollView whose
            // content is swapped underneath it, and the offset survives the swap:
            // scroll to the bottom of the long measurements step, tap Continue,
            // and the next step opens already scrolled past its own title and
            // first question. It looks like the app dropped you into the middle
            // of a form. Caught by an audit of the step screenshots — every
            // capture was mid-scroll, which is the tell.
            .id(step)
            .scrollDismissesKeyboard(.interactively)
            // `safeAreaInset` rather than a VStack sibling plus a guessed bottom
            // padding. The footer's height is not knowable in advance: at
            // accessibility sizes the two buttons stack and it grows past 190pt,
            // which is taller than any fixed padding constant here — so the last
            // row of a long step would sit under an opaque footer, existing and
            // visible but not tappable. `safeAreaInset` makes the scroll view
            // inset itself by the footer's ACTUAL height, so the clearance is
            // correct at every text size instead of correct at the one it was
            // measured against.
            //
            // `spacing` is not cosmetic padding — it is added to the inset, so
            // the clearance stays correct. With 0 the last card's rounded border
            // landed exactly on the footer's hairline divider and read as one
            // doubled line rather than a boundary.
            .safeAreaInset(edge: .bottom, spacing: AstraSpacing.sm) { footer }
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

    // Skipping is allowed, but it must not be the loudest thing on the screen.
    // Rendered as the filled champagne primary, "Skip for now" was the single
    // brightest element on a step where nothing had been answered yet — the
    // design was inviting the user to abandon exactly the questions that feed
    // Style DNA. Secondary keeps it a full-width, obvious forward action while
    // letting "Continue" own the emphasis once there is something to continue
    // with.
    //
    // Branched with `if`/`else` rather than a ternary on the style: the two
    // styles are different concrete types, so a ternary does not type-check, and
    // the usual workaround of erasing to `AnyView` would throw away SwiftUI's
    // identity for the button and re-create it on every state change.
    @ViewBuilder
    private var advanceButton: some View {
        if advanceIsSkip {
            Button(advanceTitle, action: onAdvance)
                .buttonStyle(.astraSecondary)
                .disabled(!canAdvance)
                .accessibilityIdentifier("onboarding.advance")
        } else {
            Button(advanceTitle, action: onAdvance)
                .buttonStyle(.astraPrimary)
                .disabled(!canAdvance)
                .accessibilityIdentifier("onboarding.advance")
        }
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
