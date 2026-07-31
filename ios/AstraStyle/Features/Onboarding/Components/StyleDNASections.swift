//
//  StyleDNASections.swift
//  AstraStyle
//
//  The pieces the §6.10 result screen is assembled from.
//
//  Split out of `OnboardingResultView` so that file reads as the six sections
//  spec §6.10 lists plus the states around them, rather than as four hundred
//  lines of stacks. Each type here owns one section's presentation and nothing
//  else, and none of them own any state — the screen decides what to show, and
//  these decide how it looks.
//
//  TWO RULES RUN THROUGH ALL OF THEM.
//
//  1. COLOUR IS NEVER THE ONLY CARRIER OF MEANING (spec §19). The palette is
//     the section most at risk of breaking that — a row of swatches is the
//     obvious design and is unusable for a colour-blind reader and invisible to
//     VoiceOver. So every swatch is drawn WITH its name, the "avoid" group is
//     separated by a heading rather than by a red tint, and each chip exposes a
//     single accessibility element whose label is the word, not the colour.
//
//  2. AN ABSENT SECTION IS NOT AN ERROR. Sparse input is the normal case (five
//     of the eight §6.9 axes have no imagery yet), so a missing palette or an
//     empty signature list is information, not a failure. Sections with nothing
//     to say are omitted by the screen and accounted for in the honesty block
//     instead of rendering an empty box that reads as something broken.
//

import SwiftUI

// MARK: - Palette

/// §6.10's "Preferred palette", drawn rather than described.
///
/// The names come from the server as English words (`identityPlaybook.ts`), so
/// the swatch beside each one is resolved through `AstraGarmentColor` and is
/// allowed to be absent — a build that has not heard of a colour shows the word
/// alone rather than inventing a rectangle. See that file's header.
struct StyleDNAPaletteSection: View {
    let palette: StyleDNAPalette

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "Your palette", comment: "Style DNA section title"),
                eyebrow: String(localized: "COLOUR", comment: "Style DNA section eyebrow")
            )

            if !palette.preferredColors.isEmpty {
                SwatchGroup(
                    heading: String(localized: "Build on these", comment: "Style DNA palette group"),
                    names: palette.preferredColors,
                    isAvoided: false
                )
            }

            if !palette.avoidedColors.isEmpty {
                SwatchGroup(
                    // The heading is what carries "these are the ones to leave
                    // alone". Doing it with a red tint instead would be exactly
                    // the colour-only encoding §19 forbids — on a screen made of
                    // colours, where it would also read as an error.
                    heading: String(localized: "Steer away from", comment: "Style DNA palette group"),
                    names: palette.avoidedColors,
                    isAvoided: true
                )
            }

            if !palette.rationale.isEmpty {
                Text(palette.rationale)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.result.palette")
    }
}

private struct SwatchGroup: View {
    let heading: String
    let names: [String]
    let isAvoided: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(heading)
                .astraText(.micro)
                .foregroundStyle(AstraColor.textMuted)

            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                // Keyed by position rather than by the colour name. The name is
                // content from the server and nothing guarantees it is unique
                // within one palette; a duplicate would silently drop a chip.
                ForEach(Array(AstraGarmentColor.swatches(for: names).enumerated()), id: \.offset) { _, swatch in
                    SwatchChip(swatch: swatch, isAvoided: isAvoided)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SwatchChip: View {
    let swatch: AstraSwatch
    let isAvoided: Bool

    /// Scales with the label beside it. A fixed 16pt square next to 40pt text at
    /// AX5 reads as a speck, and the whole point of the square is that it is the
    /// colour — a speck of navy and a speck of charcoal are the same speck.
    @ScaledMetric(relativeTo: .caption) private var swatchSize: CGFloat = 18

    var body: some View {
        HStack(spacing: AstraSpacing.xs) {
            if let color = swatch.color {
                Circle()
                    .fill(color)
                    .frame(width: swatchSize, height: swatchSize)
                    // Every swatch is stroked, including the dark ones. Bone and
                    // bright white are within a few points of the light-mode page
                    // and would otherwise be an invisible gap with a word next to
                    // it.
                    .overlay(Circle().strokeBorder(AstraColor.divider, lineWidth: 1))
            }

            Text(swatch.name)
                .astraText(.caption)
                .foregroundStyle(isAvoided ? AstraColor.textMuted : AstraColor.textPrimary)
                .strikethrough(isAvoided, color: AstraColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, AstraSpacing.sm)
        .padding(.vertical, AstraSpacing.xs)
        .background(
            Capsule(style: .continuous).fill(AstraColor.backgroundSecondary)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    AstraColor.divider,
                    style: StrokeStyle(lineWidth: 1, dash: swatch.color == nil ? [3, 3] : [])
                )
        )
        // One element, labelled with the word. The rectangle is decoration; a
        // VoiceOver user gets "Steer away from" from the group heading above and
        // the colour name from here, which is the whole meaning.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(swatch.name)
    }
}

// MARK: - Secondary influences

/// §6.10's "Secondary influences". Static labels, not `AstraChip` — nothing
/// here is selectable, and a chip that looks tappable and is not is a dead
/// control by any other name (spec §22's acceptance bar).
struct StyleDNAInfluencePill: View {
    let title: String

    var body: some View {
        Text(title)
            .astraText(.caption)
            .foregroundStyle(AstraColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AstraSpacing.md)
            .padding(.vertical, AstraSpacing.xs)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(AstraColor.divider, lineWidth: 1)
            )
    }
}

// MARK: - Named recommendations

/// One §6.10 "signature item opportunity": what to buy, and why that and not a
/// neighbouring piece.
struct StyleDNASignatureRow: View {
    let recommendation: StyleDNARecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(recommendation.title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(recommendation.reason)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One §6.10 "initial wardrobe priority", in the order the generator ranked it.
///
/// The numeral is drawn from `priority.rank` rather than from the row's position
/// in the list, because the model carries the rank precisely so a screen that
/// filtered or reordered would still show the number the generator meant.
///
/// It is also the only number on this screen, and that is deliberate:
/// `docs/12-design-critique.md`'s first finding is that quantifying taste turns
/// a stylist into software. A rank is a sequence, not a score — it says do this
/// one first, not your wardrobe is a 68.
struct StyleDNAPriorityRow: View {
    let priority: StyleDNAPriority

    @ScaledMetric(relativeTo: .caption) private var markerSize: CGFloat = 26

    var body: some View {
        HStack(alignment: .top, spacing: AstraSpacing.md) {
            Text("\(priority.rank)")
                .astraText(.micro)
                .foregroundStyle(AstraColor.textOnAccent)
                .monospacedDigit()
                .frame(width: markerSize, height: markerSize)
                .background(Circle().fill(AstraColor.accentChampagne))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(priority.title)
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(priority.reason)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // The circled numeral is hidden from VoiceOver above and re-stated here
        // in words, so the order is spoken as an order rather than read as a
        // stray digit before the title.
        .accessibilityLabel(
            String(
                format: String(localized: "Priority %d. %@. %@",
                               comment: "Style DNA priority, VoiceOver; rank, title, reason"),
                priority.rank, priority.title, priority.reason
            )
        )
    }
}

// MARK: - The honesty block

/// `knownInputs`, `measuredDimensions` and `openQuestions` — what the result was
/// built from and what would sharpen it.
///
/// This is not a footnote. Sparse input is the normal case, and a thin Style DNA
/// that does not say what it knew is indistinguishable from a complete one —
/// which is how a thin result ships looking finished. The step's own rationale
/// line promises "what Kyra took from your answers", and this is the half of
/// that promise the six generated sections cannot keep on their own.
///
/// Framed as what is not asked yet, never as something the user failed to do.
/// The server writes the questions that way too (`composeOpenQuestions`), and
/// re-framing them here as a checklist of omissions would undo that.
struct StyleDNAHonestySection: View {
    let knownInputs: [String]
    let openQuestions: [String]
    let measuredDimensions: [String]

    private var measuredSentence: String? {
        guard !measuredDimensions.isEmpty else { return nil }
        let names = measuredDimensions.map { raw in
            StyleDimension(rawValue: raw)?.displayName ?? raw.replacingOccurrences(of: "_", with: " ")
        }
        return String(
            format: String(localized: "The comparisons gave a read on %@.",
                           comment: "Style DNA measured axes; %@ is a list of style dimensions"),
            names.formatted(.list(type: .and))
        )
    }

    var body: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                Text("HOW THIS WAS BUILT")
                    .astraText(.micro)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)

                if !knownInputs.isEmpty {
                    LabelledList(
                        heading: String(localized: "Kyra used", comment: "Style DNA honesty heading"),
                        items: knownInputs
                    )
                    .accessibilityIdentifier("onboarding.result.knownInputs")
                }

                if let measuredSentence {
                    Text(measuredSentence)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !openQuestions.isEmpty {
                    LabelledList(
                        heading: String(localized: "Still open", comment: "Style DNA honesty heading"),
                        items: openQuestions
                    )
                    .accessibilityIdentifier("onboarding.result.openQuestions")

                    Text("Answering any of these sharpens it. None of them are required.")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct LabelledList: View {
    let heading: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(heading)
                .astraText(.micro)
                .foregroundStyle(AstraColor.textMuted)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: AstraSpacing.xs) {
                    // A rule rather than a bullet glyph: it is the mark this
                    // product's editorial register uses for a list, and it does
                    // not need to scale as a character would.
                    Rectangle()
                        .fill(AstraColor.divider)
                        .frame(width: AstraSpacing.sm, height: 1)
                        .padding(.top, AstraSpacing.sm)
                        .accessibilityHidden(true)

                    Text(item)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Editing the inputs

/// The §6.10 edit affordance: the §6.5 question again, in a sheet.
///
/// Reuses `OnboardingIdentityView` rather than reimplementing the two-stage
/// pick. Two screens asking one question in two different ways is how the rules
/// (exactly three, one primary, a fourth tap refused rather than absorbed) end
/// up enforced in one place and not the other.
struct StyleDNAIdentityEditor: View {
    /// "Regenerate" when there is a server to regenerate from, "Save" for a
    /// guest whose answers only change the draft. Named by the caller because
    /// only the caller knows which.
    let confirmTitle: String
    let onConfirm: ([StyleIdentity], StyleIdentity?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: [StyleIdentity]
    @State private var primary: StyleIdentity?

    init(
        initialSelection: [StyleIdentity],
        initialPrimary: StyleIdentity?,
        confirmTitle: String,
        onConfirm: @escaping ([StyleIdentity], StyleIdentity?) -> Void
    ) {
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        _selected = State(initialValue: initialSelection)
        _primary = State(initialValue: initialPrimary)
    }

    /// Same rule as `OnboardingDraft.hasCompleteIdentitySelection`, and for the
    /// same reason §6.5 gates the flow: two identities with no primary is not a
    /// smaller answer, it is an unusable one — and regenerating from one would
    /// produce a worse result than the user already has on screen.
    private var canConfirm: Bool {
        guard let primary else { return false }
        return selected.count == StyleIdentityRules.requiredSelectionCount
            && selected.contains(primary)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                    Text("Change these and Kyra reads your answers again. Nothing else you entered is affected.")
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    OnboardingIdentityView(selected: $selected, primary: $primary)
                }
                .padding(.horizontal, AstraSpacing.pagePadding)
                .padding(.vertical, AstraSpacing.md)
            }
            .background(AstraColor.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(Text("How do you want to look?", comment: "Style DNA edit sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: AstraSpacing.sm) {
                VStack(spacing: 0) {
                    Divider().overlay(AstraColor.divider)
                    Button(confirmTitle) {
                        onConfirm(selected, primary)
                        dismiss()
                    }
                    .buttonStyle(.astraPrimary)
                    .disabled(!canConfirm)
                    .accessibilityIdentifier("onboarding.result.editor.confirm")
                    .padding(.horizontal, AstraSpacing.pagePadding)
                    .padding(.top, AstraSpacing.sm)
                    .padding(.bottom, AstraSpacing.md)
                }
                .background(AstraColor.backgroundPrimary)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Dismiss the Style DNA edit sheet")) {
                        dismiss()
                    }
                    .foregroundStyle(AstraColor.textSecondary)
                    .accessibilityIdentifier("onboarding.result.editor.cancel")
                }
            }
        }
    }
}
