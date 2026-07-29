//
//  FitRules.swift
//  AstraStyle
//
//  The fit rule table. See `docs/14-frame-fit.md` §1 for why the `basis`
//  distinction is the most important thing in this file.
//
//  Rules are DATA, not closures. A closure-based rule cannot be enumerated,
//  printed, diffed, or asserted over — and the tone guarantee in §4 of the
//  design doc depends on being able to walk every user-facing string in the
//  table and check it. A predicate table is duller and testable; a DSL of
//  closures is elegant and unverifiable.
//

import Foundation

// MARK: - Basis

/// Why a rule is believed — and therefore how long it can be trusted.
///
/// Roughly half of received menswear fit advice follows from how shapes and
/// lines are read, and does not expire. The other half is convention that has
/// already turned over once in the last fifteen years. Encoded in one
/// undifferentiated table, the app asserts expiring blog dogma in the same
/// confident voice it uses for geometry, and there is no way to revise one
/// without auditing the other.
public enum FitRuleBasis: Hashable, Sendable {
    /// Follows from optics: where a line falls, how volume reads, what tension
    /// looks like. Does not expire.
    case optical

    /// Widely held, useful now, certain to change. Stops firing after
    /// `reviewAfter` rather than quietly continuing to be asserted.
    case convention(reviewAfter: DateComponents)

    /// Convention carries less weight than geometry even before it expires.
    var weightMultiplier: Double {
        switch self {
        case .optical: 1.0
        case .convention: 0.6
        }
    }

    func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .optical:
            return true
        case .convention(let reviewAfter):
            guard let expiry = calendar.date(from: reviewAfter) else { return false }
            return date < expiry
        }
    }
}

// MARK: - Predicates

/// Which frame a rule speaks to. `nil` on an axis means "any".
public struct FrameCondition: Hashable, Sendable {
    public var taper: FrameTaper?
    public var proportion: FrameProportion?
    public var scale: FrameScale?
    /// Requires `largeThighs` in the user's stated fit notes.
    public var requiresLargeThighs: Bool

    public init(
        taper: FrameTaper? = nil,
        proportion: FrameProportion? = nil,
        scale: FrameScale? = nil,
        requiresLargeThighs: Bool = false
    ) {
        self.taper = taper
        self.proportion = proportion
        self.scale = scale
        self.requiresLargeThighs = requiresLargeThighs
    }
}

/// How a garment's fabric behaves under load.
///
/// This is the distinction that makes the tension rule work. Two trousers of
/// identical measured width read completely differently depending on whether
/// the cloth can move: rigid cloth shows every place it is being asked to
/// stretch, fluid cloth follows the leg and stays clean.
public enum FabricBehaviour: String, Hashable, Sendable {
    /// Contains meaningful elastane/spandex, or is a knit that gives.
    case gives
    /// Selvedge, raw denim, heavy canvas, unwashed cotton twill — holds its shape.
    case rigid
    /// Not determinable from the recorded materials.
    case unknown
}

// MARK: - Rule

public struct FitRule: Hashable, Sendable, Identifiable {
    public let id: String
    public let basis: FitRuleBasis
    /// Which garments this rule can speak about.
    public let category: ClothingCategory
    /// The frame it applies to.
    public let frame: FrameCondition
    /// Garment cuts the rule addresses. Empty means any cut.
    public let fits: Set<ItemFit>
    /// Required fabric behaviour, or `nil` if the rule is cut-only.
    public let fabric: FabricBehaviour?
    /// Score adjustment in `-1...1`, before confidence and basis weighting.
    public let delta: Double
    /// Shown when the axis is confident. Assertive.
    public let reason: String
    /// Shown when the axis is not. Offered rather than asserted.
    public let suggestion: String

    public init(
        id: String,
        basis: FitRuleBasis,
        category: ClothingCategory,
        frame: FrameCondition,
        fits: Set<ItemFit> = [],
        fabric: FabricBehaviour? = nil,
        delta: Double,
        reason: String,
        suggestion: String
    ) {
        self.id = id
        self.basis = basis
        self.category = category
        self.frame = frame
        self.fits = fits
        self.fabric = fabric
        self.delta = delta
        self.reason = reason
        self.suggestion = suggestion
    }
}

// MARK: - The table

public enum FitRuleTable {

    /// Convention rules expire together on this date unless individually
    /// revised. Chosen as a date far enough out to be useful and near enough
    /// that somebody will actually have to look again.
    private static let conventionReview = DateComponents(year: 2029, month: 1, day: 1)

    // NOTE ON EVERY STRING BELOW
    //
    // The grammatical subject is the garment. Never the wearer's body. If a
    // sentence here can be rewritten to start with "you" plus a body part, it
    // is wrong and `check_ui_conventions.py` will reject it.
    //
    // The concealment euphemism every fit guide reaches for is banned outright
    // — "flattering" — because every reader hears what it implies. ui-conventions:allow
    // Saying a garment "balances" or "lengthens" or "defines" says the same
    // thing without suggesting something needed hiding.

    public static let all: [FitRule] = [

        // MARK: Tension — the rule underneath the skinny-jeans myth
        //
        // The received rule is "muscular build -> not skinny jeans". It is
        // convention, and it is wrong in a way that matters: it bans a category
        // the wearer can in fact wear well. The optical rule underneath is that
        // a garment under tension reads as ill-fitting — which rejects rigid
        // selvedge at a slim width, and permits the same width in cloth that
        // gives. Same silhouette, opposite outcome; the variable is fabric,
        // not measurement.

        FitRule(
            id: "tension.rigid-slim-bottom",
            basis: .optical,
            category: .bottom,
            frame: FrameCondition(requiresLargeThighs: true),
            fits: [.slim],
            fabric: .rigid,
            delta: -0.45,
            reason: "Rigid cloth cut this close pulls at the thigh — the strain "
                + "is what reads, not the cut.",
            suggestion: "Rigid cloth cut this close can pull at the thigh."
        ),
        FitRule(
            id: "tension.giving-slim-bottom",
            basis: .optical,
            category: .bottom,
            frame: FrameCondition(requiresLargeThighs: true),
            fits: [.slim],
            fabric: .gives,
            delta: 0.30,
            reason: "Cloth with give holds a slim line without strain.",
            suggestion: "Cloth with give usually holds a slim line without strain."
        ),
        FitRule(
            id: "tension.rigid-slim-strong-taper",
            basis: .optical,
            category: .top,
            frame: FrameCondition(taper: .strong),
            fits: [.slim],
            fabric: .rigid,
            delta: -0.35,
            reason: "A rigid slim top pulls across the chest and back before it "
                + "reaches the waist.",
            suggestion: "A rigid slim top may pull across the chest."
        ),

        // MARK: Taper — jacket and top block

        FitRule(
            id: "taper.strong-oversized-top",
            basis: .optical,
            category: .top,
            frame: FrameCondition(taper: .strong),
            fits: [.oversized],
            fabric: nil,
            delta: -0.25,
            reason: "An oversized cut adds width where the shoulder already "
                + "carries it, so the taper below stops registering.",
            suggestion: "An oversized cut adds width at the shoulder."
        ),
        FitRule(
            id: "taper.strong-tailored-outerwear",
            basis: .optical,
            category: .outerwear,
            frame: FrameCondition(taper: .strong),
            fits: [.tailored, .slim],
            fabric: nil,
            delta: 0.35,
            reason: "A suppressed waist follows the line the shoulder sets up.",
            suggestion: "A suppressed waist tends to follow the shoulder line."
        ),
        FitRule(
            id: "taper.straight-boxy-top",
            basis: .optical,
            category: .top,
            frame: FrameCondition(taper: .straight),
            fits: [.relaxed, .oversized],
            fabric: nil,
            delta: 0.25,
            reason: "A relaxed cut reads as a deliberate shape rather than "
                + "waiting on a waist to define it.",
            suggestion: "A relaxed cut reads as a deliberate shape here."
        ),
        FitRule(
            id: "taper.straight-suppressed-outerwear",
            basis: .optical,
            category: .outerwear,
            frame: FrameCondition(taper: .straight),
            fits: [.slim],
            fabric: nil,
            delta: -0.30,
            reason: "A sharply suppressed waist has to invent a shape here, and "
                + "the seams show the effort.",
            suggestion: "A sharply suppressed waist can strain at the closure."
        ),

        // MARK: Proportion — where the horizontal line falls
        //
        // Purely optical: a waistband, a hem and a shoe are horizontal lines,
        // and the eye reads the longest uninterrupted run between them.

        FitRule(
            id: "proportion.long-torso-relaxed-bottom",
            basis: .optical,
            category: .bottom,
            frame: FrameCondition(proportion: .longTorso),
            fits: [.relaxed, .oversized],
            fabric: nil,
            delta: -0.30,
            reason: "Extra cloth at the hem breaks the leg line where it is "
                + "already the shorter run.",
            suggestion: "Extra cloth at the hem shortens the leg line."
        ),
        FitRule(
            id: "proportion.long-torso-tapered-bottom",
            basis: .optical,
            category: .bottom,
            frame: FrameCondition(proportion: .longTorso),
            fits: [.slim, .tailored],
            fabric: nil,
            delta: 0.30,
            reason: "A clean taper to the shoe keeps the leg line unbroken.",
            suggestion: "A clean taper to the shoe lengthens the leg line."
        ),
        FitRule(
            id: "proportion.long-leg-relaxed-bottom",
            basis: .optical,
            category: .bottom,
            frame: FrameCondition(proportion: .longLeg),
            fits: [.relaxed, .oversized],
            fabric: nil,
            delta: 0.30,
            reason: "There is length here to spend, so a fuller leg reads as "
                + "volume rather than as excess.",
            suggestion: "A fuller leg has length to work with here."
        ),
        FitRule(
            id: "proportion.long-leg-cropped-top",
            basis: .optical,
            category: .top,
            frame: FrameCondition(proportion: .longLeg),
            fits: [.slim, .tailored],
            fabric: nil,
            delta: 0.20,
            reason: "A shorter hem puts the waistline high and keeps the two "
                + "runs in proportion.",
            suggestion: "A shorter hem raises the waistline."
        ),

        // MARK: Scale — how many breaks the line can carry

        FitRule(
            id: "scale.compact-long-outerwear",
            basis: .optical,
            category: .outerwear,
            frame: FrameCondition(scale: .compact),
            fits: [.relaxed, .oversized],
            fabric: nil,
            delta: -0.30,
            reason: "A long, full coat adds a second horizontal break to a "
                + "line that has less room to spare.",
            suggestion: "A long, full coat adds another horizontal break."
        ),
        FitRule(
            id: "scale.compact-tailored-outerwear",
            basis: .optical,
            category: .outerwear,
            frame: FrameCondition(scale: .compact),
            fits: [.tailored, .slim],
            fabric: nil,
            delta: 0.25,
            reason: "A shorter, cleaner coat keeps the run from shoulder to "
                + "shoe in one piece.",
            suggestion: "A shorter coat keeps the line in one piece."
        ),
        FitRule(
            id: "scale.tall-relaxed-top",
            basis: .optical,
            category: .top,
            frame: FrameCondition(scale: .tall),
            fits: [.relaxed, .oversized],
            fabric: nil,
            delta: 0.20,
            reason: "A fuller cut fills the frame instead of stretching to "
                + "cover it.",
            suggestion: "A fuller cut suits the length of the frame."
        ),

        // MARK: Convention — expires, and weighted lower while it lives
        //
        // Kept because it is genuinely useful advice today, and quarantined
        // because it is the half of menswear wisdom that turns over. When
        // `conventionReview` passes these stop firing rather than continuing
        // to be asserted in the same voice as the optical rules above.

        FitRule(
            id: "convention.compact-pattern-scale",
            basis: .convention(reviewAfter: conventionReview),
            category: .top,
            frame: FrameCondition(scale: .compact),
            fits: [],
            fabric: nil,
            delta: -0.12,
            reason: "A large-scale pattern currently reads as busy at this "
                + "garment size.",
            suggestion: "Large-scale patterns can read as busy at this size."
        ),
        FitRule(
            id: "convention.tall-layering-depth",
            basis: .convention(reviewAfter: conventionReview),
            category: .outerwear,
            frame: FrameCondition(scale: .tall),
            fits: [.tailored, .regular],
            fabric: nil,
            delta: 0.12,
            reason: "A longer coat is in proportion with the current cut of "
                + "the pieces under it.",
            suggestion: "A longer coat suits the current proportions."
        )
    ]

    /// Rules whose basis has not expired as of `date`.
    public static func active(on date: Date = .now) -> [FitRule] {
        all.filter { $0.basis.isActive(on: date) }
    }
}
