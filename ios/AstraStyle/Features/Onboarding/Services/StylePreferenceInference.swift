//
//  StylePreferenceInference.swift
//  AstraStyle
//
//  Turns a sequence of A/B choices into the eight-dimension preference vector
//  spec §6.9 asks for. Pure functions over values; no state, no I/O.
//
//  ────────────────────────────────────────────────────────────────────────────
//  HOW MUCH SIGNAL IS ACTUALLY IN HERE. READ THIS BEFORE TRUSTING A SCORE.
//  ────────────────────────────────────────────────────────────────────────────
//
//  §6.9 asks for eight dimensions and offers 12–20 comparisons to get them. That
//  is 1.5 to 2.5 comparisons per axis if the comparisons are spread perfectly
//  evenly, which they never are. And a forced-choice comparison is close to one
//  bit of information: it tells you which side of a line the man fell on, not
//  how far from it he stands. Someone who mildly prefers the tailored outfit and
//  someone who would never own the other one produce the identical answer.
//
//  So, plainly:
//
//    • ONE comparison on an axis gives a DIRECTION and nothing else. The score
//      it produces is ±1 because that is what "he picked this one" means — not
//      because he is at the extreme of the axis. Its confidence is `.low` and no
//      part of the app should tell the user this is what he likes.
//
//    • TWO OR THREE agreeing comparisons give a usable direction with a rough
//      magnitude. That is `.moderate`, and it is the bar at which
//      `PreferenceConfidence.isStatable` allows Kyra to say it out loud.
//
//    • FOUR OR MORE, largely agreeing, is `.high`. With eight axes to cover, at
//      most two or three axes can reach this inside a 20-comparison quiz. That
//      is a fact about the format, not a shortfall in the implementation.
//
//    • DISAGREEING ANSWERS LOWER CONFIDENCE, THEY DO NOT AVERAGE AWAY. Two
//      comparisons pointing opposite ways produce a score near zero, and a score
//      near zero from conflict must not be reported with the same confidence as
//      a score near zero from consistent middling answers. `agreement` is what
//      separates them, and it feeds the confidence band directly.
//
//    • AN AXIS NOBODY ASKED ABOUT GETS NO ENTRY AT ALL. Not 0. Not "neutral".
//      Nothing. Every one of the eight axes now gets a reading, but two of them
//      rest on a single comparison, and one
//      axes come back absent, and that is the correct output — see
//      `StyleQuizCatalog` for why the missing imagery is not stubbed.
//
//  Degrading to "no strong signal on this axis" is a RESULT, not a failure. The
//  failure mode this file exists to avoid is the opposite one: eight confident
//  numbers derived from three photographs, which reads as a finished Style DNA
//  and is a third measurement and five guesses.
//
//  ONE CONFOUND THAT NO AMOUNT OF ARITHMETIC HERE CAN FIX. `brand/quiz-imagery/README.md`
//  makes the point: if one photograph is better lit or better composed than its
//  partner, the user picks the PHOTOGRAPH and this file records it as a style
//  preference — indistinguishable, downstream, from a real one. The mitigation
//  is entirely in the imagery's prompt discipline, not here. Anyone widening
//  this quiz should read that file before generating a single new frame.
//

import Foundation

public enum StylePreferenceInference {

    // MARK: Confidence thresholds

    /// Effective observations at or above which an axis is `.moderate`,
    /// provided the answers broadly agree.
    ///
    /// "Effective" because a comparison may load on an axis at partial weight —
    /// a pair designed around formality that also, honestly, says something
    /// about contrast contributes its full weight to the first and its partial
    /// weight to the second. Two half-weight looks at an axis are worth one
    /// full-weight look, which is the arithmetic these constants encode.
    static let moderateObservationFloor = 2.0

    /// Effective observations at or above which an axis may be `.high`.
    static let highObservationFloor = 4.0

    /// How consistent answers must be for `.moderate` and `.high` respectively.
    ///
    /// `agreement` is |Σ signed loading| / Σ |loading| — 1 when every comparison
    /// pointed the same way, 0 when they cancelled exactly. For k answers one way
    /// out of n it comes to (2k − n) / n, so these two numbers are easier to read
    /// as majorities:
    ///
    ///   • 0.5  is a three-quarters majority. Three of four, six of eight.
    ///   • 0.75 is a seven-eighths majority. Four of four, seven of eight,
    ///     eleven of twelve.
    ///
    /// So a man who picked the loose cut three times out of four reaches
    /// `.moderate` — that is real evidence and treating it like a single answer
    /// would throw it away — but not `.high`, because the fourth answer says he
    /// is not consistent about it and `.high` is the band Kyra speaks from.
    static let moderateAgreementFloor = 0.5
    static let highAgreementFloor = 0.75

    // MARK: The inference

    /// Builds the eight-dimension vector from the answers given.
    ///
    /// - Parameters:
    ///   - answers: Choices, already filtered to comparisons this build has
    ///     (`StyleQuizEngine.recognisedAnswers(in:)`). An answer for an unknown
    ///     pair is skipped here too rather than trusted to have been filtered,
    ///     because this is also the function a server-side re-inference would
    ///     mirror and it should not depend on a caller's discipline.
    ///   - catalog: Supplies the loadings, and — separately and importantly —
    ///     which axes were *askable at all*. An axis the catalog can probe but
    ///     which every answer passed on comes back present with zero
    ///     observations; an axis the catalog cannot probe comes back absent.
    ///   - comparisonsOffered: How many the user was actually shown, recorded on
    ///     the vector so a stored result stays interpretable when the catalog
    ///     later grows.
    public static func vector(
        from answers: [StylePreferenceQuizAnswer],
        catalog: StyleQuizCatalog,
        comparisonsOffered: Int
    ) -> StylePreferenceVector {
        let pairsByID = Dictionary(uniqueKeysWithValues: catalog.pairs.map { ($0.id, $0) })

        // Running totals per axis. `signed` accumulates direction, `absolute`
        // accumulates how much was asked — their ratio is the score, and the
        // ratio of |signed| to absolute is the agreement.
        var signed: [StyleDimension: Double] = [:]
        var absolute: [StyleDimension: Double] = [:]
        var answeredCount = 0

        for answer in answers {
            guard let pair = pairsByID[answer.pairID] else { continue }
            answeredCount += 1

            // "No preference" is counted as answered and contributes no
            // evidence. That is the entire reason the option exists: a man who
            // is indifferent between two outfits and is made to pick one
            // contributes a coin flip, and on an axis with a single comparison
            // a coin flip IS the measurement.
            guard answer.chosenOptionID != StyleQuizPair.noPreferenceOptionID else { continue }
            guard let chosen = pair.option(withID: answer.chosenOptionID) else { continue }

            for (dimension, loading) in chosen.loadings {
                signed[dimension, default: 0] += loading
                absolute[dimension, default: 0] += abs(loading)
            }
        }

        var readings: [StyleDimension: StyleDimensionReading] = [:]
        for dimension in catalog.probedDimensions {
            let mass = absolute[dimension] ?? 0
            guard mass > 0 else {
                // Askable, but every comparison touching it was passed on.
                // Recorded rather than omitted, because "he had no opinion" and
                // "we never asked" are different facts and only one of them can
                // be fixed by asking again.
                readings[dimension] = StyleDimensionReading(
                    score: nil,
                    confidence: .insufficient,
                    observations: 0,
                    agreement: nil
                )
                continue
            }

            let total = signed[dimension] ?? 0
            let score = total / mass          // -1…+1 by construction
            let agreement = abs(total) / mass // 0…1 by construction

            readings[dimension] = StyleDimensionReading(
                score: score,
                confidence: confidence(observations: mass, agreement: agreement),
                observations: mass,
                agreement: agreement
            )
        }

        return StylePreferenceVector(
            comparisonsAnswered: answeredCount,
            comparisonsOffered: comparisonsOffered,
            dimensions: readings
        )
    }

    /// The confidence band for one axis. See the thresholds above for the
    /// reasoning behind each number.
    static func confidence(observations: Double, agreement: Double) -> PreferenceConfidence {
        guard observations > 0 else { return .insufficient }
        if observations >= highObservationFloor && agreement >= highAgreementFloor { return .high }
        if observations >= moderateObservationFloor && agreement >= moderateAgreementFloor { return .moderate }
        return .low
    }
}

// MARK: - Saying what was learned

public extension StylePreferenceInference {

    /// One line telling the user what the comparisons actually picked up on,
    /// shown when the run finishes.
    ///
    /// Derived from the vector rather than written as a fixed sentence, because
    /// a fixed sentence would be a claim about a comparison set that is content
    /// and changes underneath it. With fourteen pairs this says eight axes;
    /// with sixteen it says whatever sixteen covered, without anyone editing a
    /// string.
    ///
    /// The wording is bounded by what the numbers support. "A first read on" is
    /// as far as `.low` confidence goes, and nothing here tells the user what he
    /// likes — the whole point of `PreferenceConfidence` is that after one
    /// comparison per axis we are not entitled to. When the quiz is long enough
    /// for axes to reach `.moderate`, the stronger phrasing switches on by
    /// itself.
    static func learnedSummary(for vector: StylePreferenceVector) -> String {
        let measured = vector.measuredDimensions
        guard !measured.isEmpty else {
            // Every comparison passed on, or none answered. Not a failure, and
            // not worth apologising for.
            return String(
                localized: "No strong pull either way — which is its own answer. Kyra will work from the rest of what you've told her.",
                comment: "Style quiz summary when no comparison produced a preference"
            )
        }

        let names = measured.map(\.displayName).formatted(.list(type: .and))
        let statable = vector.statableDimensions

        if statable.count == measured.count {
            return String(
                format: String(
                    localized: "That gives Kyra a clear read on %@.",
                    comment: "Style quiz summary; %@ is a list like 'colour, formality and cut'"
                ),
                names
            )
        }

        return String(
            format: String(
                localized: "That's a first read on %@ — a starting point, not a verdict.",
                comment: "Style quiz summary; %@ is a list like 'colour, formality and cut'"
            ),
            names
        )
    }
}
