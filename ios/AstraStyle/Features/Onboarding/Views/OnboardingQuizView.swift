//
//  OnboardingQuizView.swift
//  AstraStyle
//
//  Spec §6.9 — the paired-image preference quiz. "Show paired images. Ask which
//  outfit the user would rather wear."
//
//  This step is sixth of seven on what `docs/01-build-roadmap.md` names as the
//  highest-drop-off surface in the app, and it is the only one that asks the
//  user to do the same thing repeatedly. Three things follow from that:
//
//  1. THE PHOTOGRAPH IS THE BUTTON. There is no caption under each option and no
//     confirm step — tapping the outfit chooses it and moves on. A label like
//     "Tailored" would also turn a visual comparison into a reading task and
//     anchor the answer on the word rather than the clothes.
//
//  2. "NO PREFERENCE" IS OFFERED, LOUDLY ENOUGH TO USE. A man who is indifferent
//     between two outfits and is made to pick one contributes a coin flip, and
//     on an axis carrying a single comparison that coin flip IS the measurement.
//     Passing is a better answer than a guess, so it is a visible control rather
//     than something you get by tapping neither.
//
//  3. THE COUNT IS THE REAL COUNT. Three comparisons exist, so it says "1 of 3".
//     Not "1 of 16" against imagery that has not been produced. A progress
//     indicator that stalls is the single most reliable way to lose someone
//     mid-flow, and one that is honest about being short is not a weakness —
//     three quick taps and a finish line in view is a better experience than
//     sixteen would be anyway.
//
//  The step is skippable (`OnboardingStep.isSkippable`), and leaving early is a
//  first-class outcome: whatever was answered is scored, the axes nobody reached
//  come back absent rather than neutral, and Style DNA is built to work from
//  less. See `StylePreferenceInference`.
//

import SwiftUI
import UIKit

struct OnboardingQuizView: View {
    @Binding var draft: OnboardingDraft
    let engine: StyleQuizEngine

    private var currentPair: StyleQuizPair? {
        engine.nextComparison(given: draft.quizAnswers)
    }

    private var answeredCount: Int {
        engine.answeredCount(given: draft.quizAnswers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            if engine.hasNothingToAsk {
                unavailableCard
            } else if let pair = currentPair {
                comparison(pair)
            } else {
                completionCard
            }

            if answeredCount > 0 {
                undoButton
            }
        }
        .animation(AstraMotion.standard, value: answeredCount)
    }

    // MARK: - One comparison

    @ViewBuilder
    private func comparison(_ pair: StyleQuizPair) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            progressLine(for: pair)

            // Side by side at EVERY text size, including AX5 — deliberately not
            // the one-column-at-`.accessibility1` treatment the identity grid
            // uses.
            //
            // That treatment was tried here first, on the reasoning that a man
            // who turns the text up wants the picture bigger too. Screenshots at
            // AX5 killed it: a full-width tile is 353×438pt, the title and
            // rationale above it already run to roughly half the viewport, and
            // what he actually sees is the top third of ONE outfit with the
            // other one two screens away. The question is "which of these two",
            // and an answer that requires remembering the first photograph while
            // scrolling to the second is not a comparison.
            //
            // Photographs also do not scale with Dynamic Type, so nothing here
            // truncates or clips at AX5 the way a text label would — the tiles
            // are the same size at every setting. Two full-body outfits at 170pt
            // wide read clearly (a blazer against a sweatshirt is not a fine
            // distinction), and everything that DOES carry text — the count, the
            // pass control, the footnote — scales and wraps normally around them.
            HStack(alignment: .top, spacing: AstraSpacing.sm) {
                optionTile(pair.optionA, in: pair)
                optionTile(pair.optionB, in: pair)
            }

            noPreferenceButton(for: pair)
            provenanceFootnote
        }
        // Keyed on the pair so each comparison is a fresh subtree that fades in,
        // rather than the same two image views having their contents swapped —
        // which cross-dissolves one outfit into another and reads as a glitch.
        .id(pair.id)
        .transition(.opacity)
    }

    private func progressLine(for pair: StyleQuizPair) -> some View {
        let position = engine.position(of: pair) ?? (answeredCount + 1)
        // The count sits on the `Text` itself rather than on a wrapping stack.
        // An `accessibilityElement(children: .ignore)` applied to an HStack
        // publishes an element of type `other`, so `app.staticTexts[...]` in a
        // UI test does not match it — the label is read correctly by VoiceOver
        // and is simply the wrong KIND of element for anything querying by type.
        return Text("\(position) of \(engine.comparisonCount)")
            .astraText(.micro)
            .foregroundStyle(AstraColor.textMuted)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(
                String(
                    format: String(localized: "Comparison %d of %d",
                                   comment: "Style quiz progress, VoiceOver"),
                    position, engine.comparisonCount
                )
            )
            .accessibilityIdentifier("onboarding.quiz.progress")
    }

    private func optionTile(_ option: StyleQuizOption, in pair: StyleQuizPair) -> some View {
        Button {
            choose(optionID: option.id, in: pair)
        } label: {
            QuizPhoto(url: option.imageURL)
        }
        .buttonStyle(.plain)
        // The garments, read out in the same order and at the same detail on
        // both sides — never "the formal one". Naming the axis would tell a
        // VoiceOver user which answer means what, and he would then be answering
        // a different question from everyone else. Enforced at load time:
        // `StyleQuizCatalog` drops a pair whose description is missing.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.accessibilityDescription)
        .accessibilityHint(String(localized: "Chooses this outfit and shows the next comparison",
                                  comment: "Style quiz option, VoiceOver hint"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("onboarding.quiz.option.\(pair.id).\(option.id)")
    }

    private func noPreferenceButton(for pair: StyleQuizPair) -> some View {
        Button(String(localized: "No preference", comment: "Style quiz: pass on a comparison")) {
            choose(optionID: StyleQuizPair.noPreferenceOptionID, in: pair)
        }
        .buttonStyle(.astraTertiary)
        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
        .accessibilityHint(String(localized: "Records no preference and shows the next comparison",
                                  comment: "Style quiz no-preference button, VoiceOver hint"))
        .accessibilityIdentifier("onboarding.quiz.noPreference")
    }

    /// Says what the pictures are, once, quietly.
    ///
    /// Without it a reasonable person assumes these are products Astra sells, or
    /// clothes it thinks he owns, and the first assumption is the kind that ends
    /// in a support ticket. One line, `micro`, under the fold of attention — not
    /// a badge on each tile, which would double the visual noise on the one
    /// screen in the app where the photograph IS the question.
    private var provenanceFootnote: some View {
        Text("Reference looks, not products.")
            .astraText(.micro)
            .foregroundStyle(AstraColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Finished

    private var completionCard: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text("That's all of them.")
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Derived from the vector, so it names the axes the comparisons
            // actually covered and claims only as much as the confidence
            // supports. With a short set that is "a first read on"; it
            // strengthens by itself once the comparison set is long enough for
            // an axis to reach `.moderate`, with no string rewritten.
            Text(StylePreferenceInference.learnedSummary(for: engine.vector(from: draft.quizAnswers)))
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.card).fill(AstraColor.surfaceElevated)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.quiz.complete")
    }

    /// Shown when the manifest is empty or none of its imagery made it into the
    /// build.
    ///
    /// Says so rather than rendering an empty frame or a placeholder outfit. A
    /// placeholder would be answered like a real photograph and recorded as a
    /// real preference — see `StyleQuizCatalog`. The step stays skippable and the
    /// forward button already reads "Continue", so this is a dead end for the
    /// quiz and not for the user.
    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text("Nothing to compare yet")
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("The outfit comparisons aren't available in this version. Kyra will work from everything else you've told her.")
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.card).fill(AstraColor.surfaceElevated)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.quiz.unavailable")
    }

    // MARK: - Undo

    /// Takes back the last answer.
    ///
    /// Labelled "Undo last choice", not "Back", because the footer already has a
    /// Back that leaves the step entirely and two controls called the same thing
    /// doing different things is how a user loses his place. A misfire on a
    /// full-bleed photograph that immediately advances is easy — without this the
    /// only remedy is abandoning the step.
    private var undoButton: some View {
        Button(String(localized: "Undo last choice", comment: "Style quiz: revert the previous answer")) {
            draft.quizAnswers = engine.undoingLastAnswer(in: draft.quizAnswers)
            AstraHaptics.selection()
        }
        .buttonStyle(.astraTertiary)
        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
        .accessibilityIdentifier("onboarding.quiz.undo")
    }

    // MARK: - Recording

    private func choose(optionID: String, in pair: StyleQuizPair) {
        guard let updated = engine.recording(
            pairID: pair.id,
            optionID: optionID,
            into: draft.quizAnswers
        ) else { return }
        draft.quizAnswers = updated
        AstraHaptics.selection()
    }
}

// MARK: - The photograph

/// One option's image, loaded from the bundle off the main thread.
///
/// Loaded explicitly rather than through `AsyncImage`: the URL is a `file://`
/// path into the app bundle, and routing a local read through the URL loading
/// system to get an image that is already on disk buys nothing while making the
/// failure case ("the file is not there") indistinguishable from a network one.
/// Doing it here also means the placeholder is a surface in the app's own
/// palette rather than a blank rectangle.
private struct QuizPhoto: View {
    let url: URL

    /// The shipped frames are 720×893 after the top crop the imagery pipeline
    /// applies (see `Resources/QuizImagery/README.md`). Fixing the ratio here
    /// rather than taking it from the decoded image means the two tiles are the
    /// same height before either has loaded, so the row does not reflow under
    /// the user's thumb as the images arrive.
    private static let aspectRatio: CGFloat = 720.0 / 893.0

    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
            .fill(AstraColor.surfaceElevated)
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .stroke(AstraColor.divider, lineWidth: 1)
            )
            .task(id: url) { image = await Self.load(url) }
    }

    /// `Task.detached` rather than a plain `await`. `SWIFT_APPROACHABLE_CONCURRENCY`
    /// is on for this target (see `ios/project.yml`), which makes a nonisolated
    /// async function run on its CALLER'S executor — so a helper called from
    /// `.task` would decode a JPEG on the main actor while the user is tapping.
    /// Detaching is what actually gets it off the main thread under that setting.
    private static func load(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            // Decoded straight to tile size via ImageIO rather than decoding the
            // full frame and letting the layer scale it, per spec §20's
            // "never render full-resolution originals". 240pt covers a
            // full-width tile at accessibility sizes on the largest phone.
            return ImageDownsampling.downsample(data: data, to: 240) ?? UIImage(data: data)
        }.value
    }
}

#Preview("Quiz") {
    @Previewable @State var draft = OnboardingDraft()
    return ScrollView {
        OnboardingQuizView(draft: $draft, engine: StyleQuizEngine(catalog: .bundled()))
            .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
}
