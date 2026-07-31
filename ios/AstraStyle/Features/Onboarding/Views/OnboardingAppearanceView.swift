//
//  OnboardingAppearanceView.swift
//  AstraStyle
//
//  Spec §6.7 — Appearance profile. "Explain why each is used and allow
//  omission."
//
//  That sentence is the whole design brief and it is doing more work than it
//  looks like. This is the step where a stylist app asks a man about his body
//  and face, and it is the easiest place in the product to sound like it is
//  cataloguing him. Three consequences:
//
//  1. EVERY GROUP CARRIES ITS OWN REASON, inline and in plain language. Not a
//     tooltip, not an info icon — a line of text under the question. A reason
//     the user has to tap to see is a reason he will not read, and the ask
//     stays unexplained for everyone who does not tap.
//
//  2. NOTHING IS PRE-SELECTED AND NOTHING IS REQUIRED. The whole step is
//     skippable (`OnboardingStep.isSkippable`), and each row can be cleared by
//     tapping the selected chip again — so an accidental tap is undoable
//     without hunting for a "clear" affordance.
//
//  3. TATTOOS ARE ASKED ABOUT NEUTRALLY AND USED NARROWLY. The question is
//     whether tattoos are usually visible, not whether he wants them hidden,
//     and the stated use is sleeve length. `check_ui_conventions.py` bans the
//     body-language denylist precisely so this screen cannot drift into
//     "minimise" or "conceal" phrasing.
//
//  Reference selfies (§6.7's last bullet) are NOT collected here. They have
//  their own step — §5.1 step 11, `OnboardingReferenceView` — two screens
//  later, because they are consent-gated under §29 and that consent needs a
//  screen of its own rather than a sixth question on a form about hair colour.
//  Mixing them in here would also make this whole step feel heavier than it is:
//  everything on this screen is a tap, and one of them would have opened a
//  camera.
//

import SwiftUI

struct OnboardingAppearanceView: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xl) {
            coloringSection
            featuresSection
        }
    }

    // MARK: - Coloring

    private var coloringSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "Your coloring", comment: "Onboarding section title"),
                eyebrow: String(localized: "COLOR", comment: "Onboarding section eyebrow")
            )

            ChoiceGroup(
                title: String(localized: "Skin undertone", comment: "Appearance question"),
                reason: String(localized: "Decides which neutrals Kyra suggests — warm and cool skin call for different shades of gray, navy and brown.",
                               comment: "Why skin undertone is asked"),
                options: AppearanceOptions.skinUndertones,
                selection: $draft.skinUndertone,
                identifier: "skinUndertone",
                // Undertone is not obvious and men are routinely asked it for the
                // first time here. A guess costs nothing to correct later; being
                // stuck on a question you cannot answer costs the whole step.
                hint: String(localized: "Not sure? Veins that look green lean warm, blue lean cool.",
                             comment: "Skin undertone hint")
            )

            ChoiceGroup(
                title: String(localized: "Hair color", comment: "Appearance question"),
                reason: String(localized: "Sets how much contrast an outfit should carry between its lightest and darkest pieces.",
                               comment: "Why hair color is asked"),
                options: AppearanceOptions.hairColors,
                selection: $draft.hairColor,
                identifier: "hairColor"
            )

            ChoiceGroup(
                title: String(localized: "Eye color", comment: "Appearance question"),
                reason: String(localized: "Narrows the accent colors — a knit or a tie that picks up your eyes reads as deliberate.",
                               comment: "Why eye color is asked"),
                options: AppearanceOptions.eyeColors,
                selection: $draft.eyeColor,
                identifier: "eyeColor"
            )
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "Beard, glasses, ink", comment: "Onboarding section title"),
                eyebrow: String(localized: "FEATURES", comment: "Onboarding section eyebrow")
            )

            ChoiceGroup(
                title: String(localized: "Facial hair", comment: "Appearance question"),
                reason: String(localized: "Affects which collars and necklines sit well, and keeps generated images looking like you.",
                               comment: "Why facial hair is asked"),
                options: AppearanceOptions.facialHairStyles,
                selection: $draft.facialHair,
                identifier: "facialHair"
            )

            TriStateRow(
                title: String(localized: "Do you wear glasses?", comment: "Appearance question"),
                reason: String(localized: "Frames sit in the same space as a collar and a lapel, so Kyra factors them into necklines and proportions.",
                               comment: "Why glasses are asked"),
                value: $draft.wearsGlasses,
                identifier: "wearsGlasses"
            )

            TriStateRow(
                title: String(localized: "Do you have tattoos you like to show?", comment: "Appearance question"),
                // Says what it is for AND what it is not for. The second half is
                // the part that matters: the honest worry a man has about this
                // question is that the app is about to suggest covering up.
                reason: String(localized: "Answer yes and Kyra will lean toward shorter sleeves. She'll never suggest covering anything up.",
                               comment: "Why tattoo visibility is asked"),
                value: $draft.tattoosVisible,
                identifier: "tattoosVisible"
            )
        }
    }
}

// MARK: - Components

/// A labelled question with a reason and a row of single-select chips.
private struct ChoiceGroup: View {
    let title: String
    let reason: String
    let options: [String]
    @Binding var selection: String?
    let identifier: String
    var hint: String?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(reason)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Wrapping, never a horizontal scroller. On the measurements screen
            // a horizontal chip row put the last option half off the right edge
            // with no scroll indicator — a choice the user cannot know exists.
            // Sideways scrolling is also the gesture least likely to be found by
            // someone who has enlarged the text.
            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                ForEach(options, id: \.self) { option in
                    AstraChip(
                        option,
                        isSelected: selection == option,
                        action: {
                            // Tapping the selected chip clears it. Every field
                            // here is optional, so "no answer" has to remain
                            // reachable after an accidental tap.
                            selection = selection == option ? nil : option
                            AstraHaptics.selection()
                        }
                    )
                    .accessibilityIdentifier("onboarding.appearance.\(identifier).\(Self.slug(option))")
                }
            }

            if let hint {
                Text(hint)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AstraSpacing.xxs)
            }
        }
        .padding(.bottom, typeSize.isAccessibilitySize ? AstraSpacing.sm : 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        // Reads the reason as the group's hint, so VoiceOver users get the
        // explanation §6.7 requires without having to swipe onto a separate
        // caption element.
        .accessibilityHint(reason)
    }

    /// Stable identifier fragment: lowercase, spaces to underscores.
    ///
    /// Derived from the English option rather than the displayed string so the
    /// identifiers do not change under localisation — a UI test that matches on
    /// a translated identifier passes in one language and fails in every other.
    private static func slug(_ option: String) -> String {
        option.lowercased().replacingOccurrences(of: " ", with: "_")
    }
}

/// Yes / No, with "no answer" still reachable.
///
/// A `Toggle` would be wrong here: it has two states, and this question has
/// three — yes, no, and not answered. A toggle defaulting to off would record
/// "no glasses" for every user who skipped the step, which is a fabricated
/// answer, not a missing one.
private struct TriStateRow: View {
    let title: String
    let reason: String
    @Binding var value: Bool?
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(reason)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                chip(String(localized: "Yes", comment: "Affirmative answer"), answer: true, slug: "yes")
                chip(String(localized: "No", comment: "Negative answer"), answer: false, slug: "no")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(reason)
    }

    private func chip(_ label: String, answer: Bool, slug: String) -> some View {
        AstraChip(
            label,
            isSelected: value == answer,
            action: {
                value = value == answer ? nil : answer
                AstraHaptics.selection()
            }
        )
        .accessibilityIdentifier("onboarding.appearance.\(identifier).\(slug)")
    }
}

#Preview("Appearance") {
    @Previewable @State var draft = OnboardingDraft()
    return ScrollView {
        OnboardingAppearanceView(draft: $draft)
            .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
}
