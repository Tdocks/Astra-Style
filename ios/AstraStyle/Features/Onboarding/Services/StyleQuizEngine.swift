//
//  StyleQuizEngine.swift
//  AstraStyle
//
//  Sequencing for the §6.9 paired-image quiz: which comparison comes next, what
//  a recorded choice means, and when there is enough signal to stop.
//
//  Pure. No SwiftUI, no bundle, no I/O — it is a value type over a catalog and a
//  list of answers, and every question it answers is a function of those two
//  things. That is not tidiness for its own sake: the ordering rule below is the
//  part of this feature most likely to be wrong in a way nobody notices, because
//  a badly ordered quiz still looks like a working quiz. It has to be testable
//  without a screen.
//
//  IT IS ALSO STATELESS, WHICH IS WHAT MAKES RESUMPTION WORK.
//
//  The answers live on `OnboardingDraft`, which is persisted after every change
//  (`OnboardingDraftStore`). The engine derives everything from them on demand,
//  so a user who is interrupted at comparison two and comes back tomorrow gets
//  comparison three — not because anything was saved about where he was, but
//  because there is nowhere else the sequence could resume. An engine holding
//  its own cursor would have a second source of truth to keep in sync with the
//  draft, and those two would eventually disagree.
//

import Foundation

public struct StyleQuizEngine: Sendable {

    /// Spec §6.9's upper bound. A catalog larger than this is not an error — it
    /// is a healthy content library — but a single user is asked at most twenty
    /// comparisons, because the twenty-first is a worse trade than the drop-off
    /// it costs on the highest-abandonment screen in the app.
    public static let maximumComparisons = StyleQuizCatalog.specifiedComparisonRange.upperBound

    /// Spec §6.9's lower bound, and the floor below which the early-stop rule
    /// refuses to fire no matter how confident the vector already looks.
    public static let minimumComparisonsBeforeEarlyStop =
        StyleQuizCatalog.specifiedComparisonRange.lowerBound

    public let catalog: StyleQuizCatalog

    /// The comparisons this user will be asked, in order, capped at
    /// `maximumComparisons`.
    public let comparisons: [StyleQuizPair]

    public init(catalog: StyleQuizCatalog) {
        self.catalog = catalog
        self.comparisons = Array(
            StyleQuizEngine.orderedForCoverage(catalog.pairs).prefix(Self.maximumComparisons)
        )
    }

    /// How many comparisons this run contains. The denominator the UI shows.
    public var comparisonCount: Int { comparisons.count }

    /// `true` when there is nothing to ask — no manifest, no imagery, or every
    /// pair excluded. The step still renders and is still skippable; it just has
    /// no question in it, and says so rather than showing an empty frame.
    public var hasNothingToAsk: Bool { comparisons.isEmpty }
}

// MARK: - Ordering

public extension StyleQuizEngine {

    /// Orders comparisons so that each one asks about whatever has been asked
    /// about least so far.
    ///
    /// Greedy breadth-first over the eight axes, not manifest order and not
    /// random. The reason is drop-off. `docs/01-build-roadmap.md` names
    /// onboarding as the highest-abandonment surface in the app, and this step
    /// sits sixth of seven — a meaningful share of users will answer three or
    /// four comparisons and leave. If the manifest happens to list its four
    /// colour pairs first, those users hand over a confident reading of colour
    /// and nothing at all about formality, cut, or texture. Ordered for
    /// coverage, the same four answers touch four different axes, and a partial
    /// quiz produces a thin profile rather than a lopsided one.
    ///
    /// Deterministic, which matters as much as the ordering itself: the sequence
    /// is recomputed from scratch every time a view is rebuilt or a draft is
    /// restored, so any dependence on randomness or on dictionary iteration
    /// order would let the quiz reshuffle itself underneath a user between one
    /// launch and the next.
    ///
    /// - Note: The order does NOT depend on the user's answers. An adaptive
    ///   order would be marginally more efficient — after two answers you know
    ///   which axis is least resolved rather than least *asked* — but it would
    ///   also mean that undoing a choice can change which comparison comes next,
    ///   so a user who taps Undo sees a different photograph than the one he was
    ///   just looking at. That reads as the app losing his place. Coverage is
    ///   the property worth having here; adaptivity is not.
    static func orderedForCoverage(_ pairs: [StyleQuizPair]) -> [StyleQuizPair] {
        // Manifest index is the final tiebreak, so an ordering decision is never
        // left to `Array.sorted`'s instability or to Set iteration order.
        var remaining = Array(pairs.enumerated())
        var chosen: [StyleQuizPair] = []
        var covered: [StyleDimension: Double] = [:]

        while !remaining.isEmpty {
            var bestIndex = 0
            var bestKey: (gain: Double, priority: Int, index: Int) = (
                gain: -.infinity, priority: .max, index: .max
            )

            for (position, entry) in remaining.enumerated() {
                let (manifestIndex, pair) = entry
                let gain = coverageGain(of: pair, given: covered)
                let key = (gain: gain, priority: pair.priority, index: manifestIndex)

                // Highest gain wins; then the lower `priority` value, which is
                // how content nominates the opening comparison; then manifest
                // order.
                let isBetter = key.gain > bestKey.gain
                    || (key.gain == bestKey.gain && key.priority < bestKey.priority)
                    || (key.gain == bestKey.gain && key.priority == bestKey.priority
                        && key.index < bestKey.index)
                if isBetter {
                    bestKey = key
                    bestIndex = position
                }
            }

            let (_, pair) = remaining.remove(at: bestIndex)
            for dimension in pair.probedDimensions {
                covered[dimension, default: 0] += pair.maximumLoading(on: dimension)
            }
            chosen.append(pair)
        }

        return chosen
    }

    /// How much a pair adds, given what is already covered.
    ///
    /// Each axis contributes `loading / (1 + alreadyCovered)`, so the first
    /// comparison touching an axis is worth its full loading, the second about
    /// half, the third about a third. Diminishing rather than zero, because a
    /// second look at an axis is genuinely worth something — it is what turns a
    /// direction into a confidence — just less than a first look at an untouched
    /// one.
    private static func coverageGain(
        of pair: StyleQuizPair,
        given covered: [StyleDimension: Double]
    ) -> Double {
        pair.probedDimensions.reduce(0) { total, dimension in
            total + pair.maximumLoading(on: dimension) / (1 + (covered[dimension] ?? 0))
        }
    }
}

// MARK: - Progress and sequencing

public extension StyleQuizEngine {

    /// Answers that belong to comparisons this build actually has, in the order
    /// they were given.
    ///
    /// Filtering is not defensive padding. The catalog is content: a draft saved
    /// against a three-pair build can be restored by a build with sixteen, and a
    /// pair can be pulled after its photography is rejected. An answer whose pair
    /// no longer exists cannot be scored — there are no loadings to apply — and
    /// counting it anyway would inflate the progress denominator's numerator and
    /// leave the user stuck at "4 of 3".
    func recognisedAnswers(
        in answers: [StylePreferenceQuizAnswer]
    ) -> [StylePreferenceQuizAnswer] {
        let known = Set(comparisons.map(\.id))
        var seen: Set<String> = []
        return answers.filter { answer in
            guard known.contains(answer.pairID) else { return false }
            // Last-write-wins is handled at the call site by replacing in place;
            // this guards the case where a draft from an older build somehow
            // holds two answers for one pair, which would otherwise be counted
            // twice.
            return seen.insert(answer.pairID).inserted
        }
    }

    /// The next comparison to show, or `nil` when the run is finished.
    func nextComparison(given answers: [StylePreferenceQuizAnswer]) -> StyleQuizPair? {
        let answered = Set(recognisedAnswers(in: answers).map(\.pairID))
        guard !hasEnoughSignal(given: answers) else { return nil }
        return comparisons.first { !answered.contains($0.id) }
    }

    /// 1-based position of the comparison currently being asked, for "3 of 12".
    /// `nil` once the run is finished.
    func position(of pair: StyleQuizPair) -> Int? {
        comparisons.firstIndex(where: { $0.id == pair.id }).map { $0 + 1 }
    }

    func answeredCount(given answers: [StylePreferenceQuizAnswer]) -> Int {
        recognisedAnswers(in: answers).count
    }

    func isFinished(given answers: [StylePreferenceQuizAnswer]) -> Bool {
        nextComparison(given: answers) == nil
    }

    /// Whether the run can stop before working through every available
    /// comparison.
    ///
    /// Two conditions, both required:
    ///
    ///   1. At least `minimumComparisonsBeforeEarlyStop` (spec §6.9's floor of
    ///      12) have been answered. Stopping under that would be reading the
    ///      spec's range as advisory when it is the reason the quiz is
    ///      trustworthy at all.
    ///   2. Every axis the remaining comparisons could still speak to has
    ///      already reached `.moderate`. Asking a question whose answer cannot
    ///      change what we believe is asking for nothing.
    ///
    /// WITH THE IMAGERY THAT EXISTS TODAY THIS CAN NEVER FIRE, and that is worth
    /// stating plainly rather than leaving for someone to discover: three
    /// comparisons is under the floor of twelve, so condition 1 alone settles it.
    /// It is implemented now because the alternative — adding a stopping rule
    /// later, once the quiz is long enough for it to matter — means adding it to
    /// a screen that already has users on it.
    func hasEnoughSignal(given answers: [StylePreferenceQuizAnswer]) -> Bool {
        let recognised = recognisedAnswers(in: answers)
        let answeredIDs = Set(recognised.map(\.pairID))
        let remaining = comparisons.filter { !answeredIDs.contains($0.id) }
        if remaining.isEmpty { return true }
        guard recognised.count >= Self.minimumComparisonsBeforeEarlyStop else { return false }

        let vector = StylePreferenceInference.vector(
            from: recognised,
            catalog: catalog,
            comparisonsOffered: comparisonCount
        )
        let stillReachable = remaining.reduce(into: Set<StyleDimension>()) {
            $0.formUnion($1.probedDimensions)
        }
        return stillReachable.allSatisfy { vector.confidence(for: $0).isStatable }
    }

    /// The vector implied by the answers so far.
    ///
    /// On the engine as well as on `StylePreferenceInference` because the two
    /// have to agree about which answers count — `recognisedAnswers` is the
    /// filter, and having one entry point means a caller cannot accidentally
    /// score a stale answer that the progress indicator is ignoring.
    func vector(from answers: [StylePreferenceQuizAnswer]) -> StylePreferenceVector {
        StylePreferenceInference.vector(
            from: recognisedAnswers(in: answers),
            catalog: catalog,
            comparisonsOffered: comparisonCount
        )
    }
}

// MARK: - Recording a choice

public extension StyleQuizEngine {

    /// Records a choice, returning the updated answer list.
    ///
    /// Returns the list rather than mutating one in place because the answers
    /// live on `OnboardingDraft`, which is a value type that the flow persists
    /// on every change. Handing the caller a new array keeps the engine free of
    /// any opinion about where the answers are stored.
    ///
    /// Re-answering an existing pair replaces the earlier answer IN PLACE rather
    /// than appending. Order is meaningful — it is the order the user was asked
    /// — and appending would both duplicate the pair and make an undo-then-
    /// reanswer look, to `recognisedAnswers`, like an answer the user never gave.
    ///
    /// - Returns: The updated answers, or `nil` if the choice was not valid for
    ///   that pair. Nil rather than a silent no-op so a caller cannot mistake a
    ///   rejected write for a successful one; in practice the UI only ever
    ///   passes ids it read off the pair.
    func recording(
        pairID: String,
        optionID: String,
        into answers: [StylePreferenceQuizAnswer]
    ) -> [StylePreferenceQuizAnswer]? {
        guard let pair = comparisons.first(where: { $0.id == pairID }) else { return nil }
        guard optionID == StyleQuizPair.noPreferenceOptionID || pair.option(withID: optionID) != nil else {
            return nil
        }

        let answer = StylePreferenceQuizAnswer(pairID: pairID, chosenOptionID: optionID)
        var updated = answers
        if let existing = updated.firstIndex(where: { $0.pairID == pairID }) {
            updated[existing] = answer
        } else {
            updated.append(answer)
        }
        return updated
    }

    /// Removes the most recent answer, for the quiz's own undo.
    ///
    /// "Most recent" is the last recognised answer, not the last element of the
    /// array: an answer for a pair this build no longer has must not be what an
    /// undo tap removes, or the tap appears to do nothing.
    func undoingLastAnswer(
        in answers: [StylePreferenceQuizAnswer]
    ) -> [StylePreferenceQuizAnswer] {
        guard let last = recognisedAnswers(in: answers).last else { return answers }
        var updated = answers
        updated.removeAll { $0.pairID == last.pairID }
        return updated
    }
}
