//
//  FrameHarmonyScorer.swift
//  AstraStyle
//
//  Scores a garment against the wearer's frame and produces the user-facing
//  reasons that go with the score.
//
//  Two properties matter more than the arithmetic:
//
//    1. It RANKS, it never FILTERS. A frame-suboptimal garment can still be
//       the top recommendation if colour, occasion and stated preference
//       favour it. A bad ranking costs a slightly worse suggestion; a bad
//       filter makes a garment the user owns and likes vanish from an app
//       whose whole job is to use what he already has.
//
//    2. An empty frame is a first-class case, not an edge case. Spec §6.6
//       requires "I don't know" on every field, so most users will have
//       partial data and many will have none. With no frame, this contributes
//       nothing and the app behaves exactly as it did before it existed.
//
//  See `docs/14-frame-fit.md` §3.
//

import Foundation

public struct FrameHarmonyResult: Hashable, Sendable {
    /// `0...1`, where `neutral` means "nothing to say about this garment".
    public let score: Double
    /// User-facing, garment-subject, already phrased for the confidence level.
    public let reasons: [String]
    /// `true` when the frame was too thin to say anything and the caller should
    /// fall back to pre-frame behaviour rather than treating `score` as a signal.
    public let isUninformative: Bool

    public init(score: Double, reasons: [String], isUninformative: Bool) {
        self.score = score
        self.reasons = reasons
        self.isUninformative = isUninformative
    }

    public static let uninformative = FrameHarmonyResult(
        score: FrameHarmonyScorer.neutral,
        reasons: [],
        isUninformative: true
    )
}

public enum FrameHarmonyScorer {

    /// The score a garment gets when no rule has anything to say about it.
    ///
    /// Deliberately not `0.5`. A garment nothing objects to is closer to fine
    /// than to average, and starting at the midpoint would make every
    /// unremarkable item look like a compromise in the §6.13 meter.
    public static let neutral = 0.75

    /// Above this, a rule states its reason; below, it offers a suggestion.
    ///
    /// The threshold is the whole point of carrying confidence around. Asserting
    /// "a clean taper keeps the leg line unbroken" from a lettered shirt size and
    /// a guessed inseam is how a styling app earns the user's contempt.
    public static let assertionThreshold = 0.5

    /// A rule weaker than this is left out of the reasons entirely, however
    /// certain we are of the frame. It still moves the score — it just is not
    /// worth a line of the user's attention, and the "why it works" copy is
    /// worth more when it is short.
    public static let mentionThreshold = 0.10

    /// Below this confidence a rule says nothing at all, not even hedged.
    /// There is a point where "this might apply" is not information, and
    /// filling the UI with maybes is its own kind of dishonesty.
    public static let mentionConfidenceFloor = 0.25

    /// Scores one garment against a frame.
    ///
    /// - Parameters:
    ///   - item: The garment under consideration.
    ///   - frame: The wearer's derived frame. `.unknown` is normal.
    ///   - statedFitIssues: Straight off `BodyProfile.fitNotes`. Read here
    ///     rather than folded into `frame` because `largeThighs` is a fact
    ///     about legs — filing it into a torso axis would change advice about
    ///     jackets, which is not what the user said.
    ///   - date: Injected so the convention-expiry behaviour is testable
    ///     without waiting three years.
    public static func score(
        item: ClosetItem,
        frame: FrameProfile,
        statedFitIssues: [FitIssue] = [],
        on date: Date = .now
    ) -> FrameHarmonyResult {
        guard !frame.isEmpty || statedFitIssues.contains(.largeThighs) else {
            return .uninformative
        }

        var total = neutral
        var reasons: [String] = []
        var firedAny = false

        for rule in FitRuleTable.active(on: date) {
            guard rule.category == item.category else { continue }
            guard matches(rule: rule, item: item, frame: frame, statedFitIssues: statedFitIssues)
            else { continue }

            let confidence = confidence(for: rule, in: frame, statedFitIssues: statedFitIssues)
            guard confidence > 0 else { continue }

            firedAny = true
            total += rule.delta * confidence * rule.basis.weightMultiplier

            // Whether to MENTION a rule keys off the rule's intrinsic strength;
            // whether to mention it ASSERTIVELY keys off confidence. These are
            // two different questions and the first draft conflated them by
            // thresholding on `delta × confidence`, which had a consequence
            // that only showed up in test: a strong rule at low confidence
            // produced no output at all, so `suggestion` — the entire hedged
            // voice — was unreachable for exactly the users it was written for.
            //
            // Keeping them separate means a rule that matters is always
            // surfaced, phrased honestly for how much we actually know.
            let strength = abs(rule.delta) * rule.basis.weightMultiplier
            if strength >= mentionThreshold && confidence >= mentionConfidenceFloor {
                reasons.append(confidence >= assertionThreshold ? rule.reason : rule.suggestion)
            }
        }

        guard firedAny else { return .uninformative }

        return FrameHarmonyResult(
            score: max(0, min(1, total)),
            reasons: reasons,
            isUninformative: false
        )
    }

    /// Scores a whole outfit as the mean of its garments' informative scores.
    ///
    /// Garments nothing applies to are excluded rather than counted as neutral.
    /// Averaging in a shrug for every accessory would drag a strong result
    /// toward the middle and make the meter insensitive to the pieces that
    /// actually carry the silhouette.
    public static func score(
        items: [ClosetItem],
        frame: FrameProfile,
        statedFitIssues: [FitIssue] = [],
        on date: Date = .now
    ) -> FrameHarmonyResult {
        let results = items
            .map { score(item: $0, frame: frame, statedFitIssues: statedFitIssues, on: date) }
            .filter { !$0.isUninformative }

        guard !results.isEmpty else { return .uninformative }

        let mean = results.map(\.score).reduce(0, +) / Double(results.count)
        return FrameHarmonyResult(
            score: mean,
            reasons: results.flatMap(\.reasons),
            isUninformative: false
        )
    }

    // MARK: - Matching

    private static func matches(
        rule: FitRule,
        item: ClosetItem,
        frame: FrameProfile,
        statedFitIssues: [FitIssue]
    ) -> Bool {
        if rule.frame.requiresLargeThighs && !statedFitIssues.contains(.largeThighs) {
            return false
        }
        if let required = rule.frame.taper, frame.taper?.value != required { return false }
        if let required = rule.frame.proportion, frame.proportion?.value != required { return false }
        if let required = rule.frame.scale, frame.scale?.value != required { return false }

        if !rule.fits.isEmpty {
            guard let fit = item.fit, rule.fits.contains(fit) else { return false }
        }

        if let required = rule.fabric {
            // An unknown fabric never satisfies a fabric-dependent rule. This is
            // the conservative direction on purpose: the tension rules are the
            // ones that penalise, and penalising a garment because we could not
            // read its composition would be a guess presented as a judgement.
            guard behaviour(of: item) == required else { return false }
        }

        return true
    }

    /// The confidence to apply to a rule, taken from the axes it depends on.
    ///
    /// A rule keyed on two axes is only as trustworthy as the weaker one.
    private static func confidence(
        for rule: FitRule,
        in frame: FrameProfile,
        statedFitIssues: [FitIssue]
    ) -> Double {
        var confidences: [Double] = []
        if rule.frame.taper != nil, let axis = frame.taper { confidences.append(axis.confidence) }
        if rule.frame.proportion != nil, let axis = frame.proportion {
            confidences.append(axis.confidence)
        }
        if rule.frame.scale != nil, let axis = frame.scale { confidences.append(axis.confidence) }
        // A stated fit issue is the user's own account of his body. Full confidence.
        if rule.frame.requiresLargeThighs, statedFitIssues.contains(.largeThighs) {
            confidences.append(1)
        }
        return confidences.min() ?? 0
    }

    // MARK: - Fabric behaviour

    private static let givingMarkers = [
        "elastane", "spandex", "lycra", "stretch", "jersey", "ponte", "modal",
        "rib", "knit", "terry", "french terry"
    ]

    private static let rigidMarkers = [
        "selvedge", "selvage", "raw denim", "canvas", "duck", "moleskin",
        "waxed", "cordura", "rigid"
    ]

    /// Reads fabric behaviour out of `ClosetItem.material`, which is free text.
    ///
    /// Returns `.unknown` freely. The alternative — defaulting to `.rigid` so
    /// the tension rules fire more often — would penalise every garment whose
    /// composition simply was not recorded, which is most of a scanned closet.
    static func behaviour(of item: ClosetItem) -> FabricBehaviour {
        let materials = item.material.map { $0.lowercased() }
        guard !materials.isEmpty else { return .unknown }

        // Give wins over rigidity: 98% cotton / 2% elastane is a stretch fabric,
        // not a rigid one, and the elastane is the part that governs how it moves.
        if materials.contains(where: { m in givingMarkers.contains(where: m.contains) }) {
            return .gives
        }
        if materials.contains(where: { m in rigidMarkers.contains(where: m.contains) }) {
            return .rigid
        }
        // Denim with nothing else recorded is rigid by default — unqualified
        // "denim" in a closet scan is far more often 100% cotton than stretch.
        if materials.contains(where: { $0.contains("denim") }) { return .rigid }

        return .unknown
    }
}
