//
//  OnboardingResultView.swift
//  AstraStyle
//
//  Spec §6.10 — Style DNA result. The screen the other seven steps exist to
//  reach, and the first thing in the app that is Kyra talking rather than Kyra
//  asking.
//
//  IT RENDERS SIX SECTIONS AND THREE HONESTY FIELDS, AND THE THREE ARE NOT A
//  FOOTNOTE. §6.10 lists primary identity, secondary influences, palette,
//  silhouette direction, signature opportunities and wardrobe priorities.
//  `StyleDNA` carries all six plus `knownInputs`, `openQuestions` and
//  `measuredDimensions`, and the step's own rationale line already promises
//  "What Kyra took from your answers." A screen that showed the six and dropped
//  the three would show a result built from two answers exactly as confidently
//  as one built from twelve — which is the specific dishonesty the model, the
//  migration and the Edge Function were all written to prevent.
//
//  THREE OUTCOMES, ALL OF WHICH ARE NORMAL.
//
//  1. A full profile. Every section has something in it.
//  2. A SPARSE profile — the common case, not an edge case. Five of the eight
//     §6.9 dimensions have no imagery yet, so they arrive absent, and a man who
//     skipped measurements and lifestyle gets a shorter result. Sections with
//     nothing in them are omitted rather than rendered as empty boxes, and
//     `openQuestions` says what would sharpen it. Presented as information, not
//     as a failure: nothing on this screen calls a short result incomplete.
//  3. NO PRIMARY IDENTITY AT ALL. The endpoint returns null rather than
//     guessing when neither the identity step nor a dress code has been
//     answered, and this screen must not undo that by supplying a fallback.
//     There is no default identity anywhere in this file. The headline says
//     Kyra has not called a direction, the server's own sentence explains why,
//     and the one control offered is the question that would fix it.
//
//  WHY THE FORWARD BUTTON NO LONGER SUBMITS. See `OnboardingViewModel`'s
//  header: generating before writing the answers would read an empty
//  `style_profiles` row and give every brand-new user outcome 3 above.
//

import SwiftUI

struct OnboardingResultView: View {
    let model: OnboardingViewModel

    @State private var isEditingIdentity = false

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxl) {
            // Above the result, and deliberately not blocking it. The photo is
            // optional and the answers are not, so a failed upload never fails
            // the submission — but it must not be swallowed either, or the man
            // who added a photograph would land on Home believing it saved.
            // This is the only place it can be reported, because the upload
            // runs during the submission this screen triggers.
            if let failure = model.referenceUploadFailure {
                referenceUploadNotice(failure)
            }

            switch model.styleDNAState {
            case .idle, .loading:
                workingState
            case .ready(let dna):
                result(dna, isRegenerating: false)
            case .regenerating(let dna):
                result(dna, isRegenerating: true)
            case .failed(let message, let previous):
                failureNotice(message)
                if let previous {
                    // The previous result stays on screen behind the notice.
                    // Blanking it would punish the user for a failed network
                    // call by taking away something that had already arrived.
                    result(previous, isRegenerating: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Submits the answers, then generates. Guarded inside the view model so
        // a re-run of this task cannot cost a second generation.
        .task { await model.loadStyleDNA() }
        .sheet(isPresented: $isEditingIdentity) {
            StyleDNAIdentityEditor(
                initialSelection: model.draft.selectedIdentities,
                initialPrimary: model.draft.primaryIdentity,
                confirmTitle: confirmTitle,
                onConfirm: { identities, primary in
                    Task { await model.regenerate(identities: identities, primary: primary) }
                }
            )
        }
    }

    /// Split out of the view only because the sentence is longer than one
    /// line of source. It is one paragraph on screen.

    private var confirmTitle: String {
        String(localized: "Regenerate", comment: "Confirm an edit and regenerate Style DNA")
    }

    // MARK: - States around the result

    private var workingState: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            ProgressView()
                .tint(AstraColor.accentChampagne)
                .accessibilityHidden(true)

            Text("Reading your answers.")
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)

            Text("Kyra is saving everything you entered and working through it.")
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.result.loading")
    }

    private func failureNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            // The state is named in words as well as tinted, per spec §19 — a
            // warning colour on its own is not a message.
            Text("That didn't come back.")
                .astraText(.headline)
                .foregroundStyle(AstraColor.warningAmber)

            Text(message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Nothing you entered has been lost.")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)

            Button(String(localized: "Try again", comment: "Retry Style DNA generation")) {
                Task { await model.retryStyleDNA() }
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("onboarding.result.retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .fill(AstraColor.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .strokeBorder(AstraColor.warningAmber, lineWidth: 1)
        )
    }

    // MARK: - The result itself

    @ViewBuilder
    private func result(_ dna: StyleDNA, isRegenerating: Bool) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxl) {
            if isRegenerating {
                regeneratingNotice
            }

            identitySection(dna)

            if !dna.secondaryInfluences.isEmpty {
                influencesSection(dna.secondaryInfluences)
            }

            if !dna.palette.preferredColors.isEmpty
                || !dna.palette.avoidedColors.isEmpty
                || !dna.palette.rationale.isEmpty {
                StyleDNAPaletteSection(palette: dna.palette)
            }

            if !dna.silhouette.headline.isEmpty || !dna.silhouette.detail.isEmpty {
                silhouetteSection(dna.silhouette)
            }

            if !dna.signatureOpportunities.isEmpty {
                signatureSection(dna.signatureOpportunities)
            }

            if !dna.wardrobePriorities.isEmpty {
                prioritySection(dna.wardrobePriorities)
            }

            if !dna.knownInputs.isEmpty || !dna.openQuestions.isEmpty || !dna.measuredDimensions.isEmpty {
                StyleDNAHonestySection(
                    knownInputs: dna.knownInputs,
                    openQuestions: dna.openQuestions,
                    measuredDimensions: dna.measuredDimensions
                )
            }
        }
        // Held on screen and dimmed while a regenerate is in flight, rather than
        // replaced by a spinner. The exit criterion is that the result visibly
        // CHANGES; a blank screen in between makes the change impossible to see.
        .opacity(isRegenerating ? 0.45 : 1)
        .allowsHitTesting(!isRegenerating)
        .astraAnimation(AstraMotion.standard, value: isRegenerating)
    }

    private var regeneratingNotice: some View {
        HStack(spacing: AstraSpacing.sm) {
            ProgressView()
                .tint(AstraColor.accentChampagne)
                .accessibilityHidden(true)

            Text("Reading your new picks.")
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.result.regenerating")
    }

    // MARK: §6.10 — Primary style identity

    @ViewBuilder
    private func identitySection(_ dna: StyleDNA) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            if let identity = dna.primaryIdentity {
                Text("YOUR DIRECTION")
                    .astraText(.micro)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)

                Text(identity.displayName)
                    .astraText(.displayL)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.result.identity")

                // An identity the server INFERRED is labelled as one. Presenting
                // a guess in the same voice as a choice the user made is how a
                // guess becomes a fact he never checked — and `identityBasis`
                // exists on the model for exactly this distinction.
                if dna.identityWasInferred {
                    Text("A starting point, not something you told us.")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.warningAmber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !dna.identityBasis.isEmpty {
                    Text(dna.identityBasis)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                // No fallback identity. The server declined to invent one and
                // inventing one here would put back exactly the fabrication it
                // refused to commit.
                Text("Kyra hasn't called a direction yet.")
                    .astraText(.title1)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.result.identity")
            }

            if !dna.summary.isEmpty {
                Text(dna.summary)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AstraSpacing.xs)
            }

            editButton
                .padding(.top, AstraSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The edit affordance, and the whole of §6.10's "edit and regenerate".
    ///
    /// There is deliberately no bare "Regenerate" button beside it. Regenerating
    /// an unchanged profile returns an identical document by design — the
    /// generator is deterministic — so a standalone regenerate would be a
    /// control that reliably appears to do nothing, which is worse than not
    /// offering it. Regeneration is the consequence of an edit, which is also
    /// the only reading of §6.10 under which the result stays a derivation of
    /// the user's answers. `OnboardingViewModel.regenerate` carries the longer
    /// argument for why identity is the input that gets this shortcut.
    private var editButton: some View {
        Button(editButtonTitle) {
            isEditingIdentity = true
        }
        .buttonStyle(.astraTertiary)
        .disabled(model.isWorkingOnStyleDNA)
        .accessibilityIdentifier("onboarding.result.edit")
        .accessibilityHint(Text("Opens your three style picks so you can change them",
                                comment: "Style DNA edit button hint"))
    }

    private var editButtonTitle: String {
        model.draft.selectedIdentities.isEmpty
            ? String(localized: "Choose your directions", comment: "Style DNA edit button")
            : String(localized: "Edit your picks", comment: "Style DNA edit button")
    }
}

// MARK: - The remaining §6.10 sections, and the §5.1 step 11 notice
//
// In an extension purely so the type above stays a readable account of the
// screen's STATES — working, failed, result — rather than four hundred
// lines in which those states are hard to find among the stacks.

private extension OnboardingResultView {

    /// The photo did not upload. Says so, offers to try again, and gets out of
    /// the way — nothing here can stop the user finishing.
    func referenceUploadNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text("Your photo didn't upload.")
                .astraText(.headline)
                .foregroundStyle(AstraColor.warningAmber)

            Text(message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Everything else you entered was saved, and you can carry on without it.")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button(String(localized: "Try the photo again", comment: "Retry the reference photo upload")) {
                Task { await model.retryReferenceUpload() }
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("onboarding.result.retryPhoto")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .fill(AstraColor.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .strokeBorder(AstraColor.warningAmber, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.result.photoNotice")
    }

    // MARK: §6.10 — Secondary influences

    func influencesSection(_ influences: [StyleIdentity]) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(
                title: String(localized: "Also in the mix", comment: "Style DNA section title"),
                eyebrow: String(localized: "SECONDARY INFLUENCES", comment: "Style DNA section eyebrow")
            )

            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                ForEach(influences, id: \.self) { influence in
                    StyleDNAInfluencePill(title: influence.displayName)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.result.influences")
    }

    // MARK: §6.10 — Best silhouette direction

    func silhouetteSection(_ silhouette: StyleDNASilhouette) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(
                title: String(localized: "How it should sit", comment: "Style DNA section title"),
                eyebrow: String(localized: "SILHOUETTE", comment: "Style DNA section eyebrow")
            )

            if !silhouette.headline.isEmpty {
                Text(silhouette.headline)
                    .astraText(.title2)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !silhouette.detail.isEmpty {
                Text(silhouette.detail)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.result.silhouette")
    }

    // MARK: §6.10 — Signature item opportunities

    func signatureSection(_ items: [StyleDNARecommendation]) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "Pieces worth owning", comment: "Style DNA section title"),
                eyebrow: String(localized: "SIGNATURE", comment: "Style DNA section eyebrow")
            )

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().overlay(AstraColor.divider)
                }
                StyleDNASignatureRow(recommendation: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.result.signatures")
    }

    // MARK: §6.10 — Initial wardrobe priorities

    func prioritySection(_ priorities: [StyleDNAPriority]) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "Start here", comment: "Style DNA section title"),
                eyebrow: String(localized: "IN ORDER", comment: "Style DNA section eyebrow")
            )

            ForEach(priorities) { priority in
                StyleDNAPriorityRow(priority: priority)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.result.priorities")
    }
}
