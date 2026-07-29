//
//  FrameProfile.swift
//  AstraStyle
//
//  The wearer's proportions, derived from `BodyProfile` (spec §6.6 / §9).
//  See `docs/14-frame-fit.md` for the full design and its reasoning.
//
//  Three orthogonal axes, deliberately NOT one archetype label. A single
//  label is a box; the box acquires a name; the name gets surfaced somewhere
//  in the UI six months later — which is precisely what spec §2's ban on
//  shaming body type exists to prevent. Three continuous axes carry the same
//  information with nothing to name.
//
//  Somatotype vocabulary (ectomorph / mesomorph / endomorph) is deliberately
//  absent even though the menswear trade uses it casually. It originates in
//  Sheldon's 1940s constitutional psychology, which tied body shape to
//  personality and criminality and is discredited. It is also less precise
//  than the drop measurement tailors have used for a century.
//

import Foundation

// MARK: - Axis values

/// How much the torso narrows from chest to waist — the tailoring "drop".
///
/// Drives jacket suppression, top-block fit, and whether a boxy cut reads as
/// intentional or as ill-fitting.
public enum FrameTaper: String, Codable, CaseIterable, Sendable {
    /// Drop of roughly 4" or less. Graded "straight" in tailoring.
    case straight
    /// Drop of roughly 5–6". The standard "regular" grade.
    case moderate
    /// Drop of roughly 7" or more. Graded "athletic".
    case strong
}

/// Leg length relative to total height.
///
/// Drives rise, break, waistband height, and where to place the one strong
/// horizontal line an outfit can afford.
public enum FrameProportion: String, Codable, CaseIterable, Sendable {
    case longTorso = "long_torso"
    case balanced
    case longLeg = "long_leg"
}

/// Overall size band.
///
/// Drives how many horizontal breaks an outfit can carry and how deep the
/// layering can go before the line is chopped up.
public enum FrameScale: String, Codable, CaseIterable, Sendable {
    case compact
    case average
    case tall
}

// MARK: - Axis wrapper

/// A derived axis value together with how much the derivation should be
/// trusted.
///
/// Confidence is not decoration. Spec §6.6 requires "I don't know" on every
/// measurement field, so **most users will have partial data and many will
/// have none** — and advice asserted confidently from thin data is the single
/// fastest way to make a styling app feel stupid. Confidence flows all the way
/// through to the phrasing: the same rule becomes a suggestion at 0.3 and a
/// reason at 0.9.
public struct FrameAxis<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public let value: Value
    /// `0...1`. Clamped on init — a confidence of 1.4 is a bug, not a strong opinion.
    public let confidence: Double

    public init(_ value: Value, confidence: Double) {
        self.value = value
        self.confidence = Swift.max(0, Swift.min(1, confidence))
    }
}

// MARK: - Profile

/// The wearer's frame, as far as we can tell.
///
/// Every axis is optional. A profile where all three are `nil` is the normal
/// state for a user who skipped the measurements step, and everything
/// downstream must behave exactly as it did before this type existed —
/// see `FrameHarmonyScorer` and the blend in `CompatibilityBreakdown`.
public struct FrameProfile: Codable, Hashable, Sendable {
    public var taper: FrameAxis<FrameTaper>?
    public var proportion: FrameAxis<FrameProportion>?
    public var scale: FrameAxis<FrameScale>?

    /// Neck circumference relative to chest, normalised to roughly `0...1`.
    ///
    /// Separates muscular from broad at the same chest measurement: a 46"
    /// chest with a 16.5" neck and a 46" chest with a 15" neck want different
    /// armholes and behave differently under tension. Not an axis in its own
    /// right — it modulates the tension rules rather than standing alone, and
    /// giving it axis status would imply a precision it does not have.
    public var muscularityHint: Double?

    public init(
        taper: FrameAxis<FrameTaper>? = nil,
        proportion: FrameAxis<FrameProportion>? = nil,
        scale: FrameAxis<FrameScale>? = nil,
        muscularityHint: Double? = nil
    ) {
        self.taper = taper
        self.proportion = proportion
        self.scale = scale
        self.muscularityHint = muscularityHint
    }

    /// An entirely unknown frame. The default, and the case that must not regress.
    public static let unknown = FrameProfile()

    /// `true` when nothing is known and frame scoring should contribute nothing.
    public var isEmpty: Bool {
        taper == nil && proportion == nil && scale == nil
    }

    /// The strongest confidence across the known axes, or `0` when none are known.
    ///
    /// Used to collapse the silhouette blend back to its pre-frame behaviour —
    /// see `CompatibilityBreakdown.silhouetteCompatibility`.
    public var overallConfidence: Double {
        [taper?.confidence, proportion?.confidence, scale?.confidence]
            .compactMap { $0 }
            .max() ?? 0
    }

    // MARK: - Codable
    //
    // Hand-written to FLATTEN each axis into the two columns `body_profiles`
    // actually has (`frame_taper` + `frame_taper_confidence`), rather than
    // encoding `FrameAxis` as a nested object. Synthesised Codable would
    // produce `{"frame_taper": {"value": "strong", "confidence": 0.9}}`, which
    // no column accepts — the mismatch would compile cleanly and fail at the
    // first decode against real data. This project has already been bitten
    // several times by Swift/Postgres shape drift that only surfaces at
    // runtime; `scripts/check_schema_drift.py` guards the enum cases, and this
    // encoder guards the shape.

    enum CodingKeys: String, CodingKey {
        case taper = "frame_taper"
        case taperConfidence = "frame_taper_confidence"
        case proportion = "frame_proportion"
        case proportionConfidence = "frame_proportion_confidence"
        case scale = "frame_scale"
        case scaleConfidence = "frame_scale_confidence"
        case muscularityHint = "muscularity_hint"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func axis<V: Codable & Hashable & Sendable>(
            _ valueKey: CodingKeys,
            _ confidenceKey: CodingKeys,
            as type: V.Type
        ) throws -> FrameAxis<V>? {
            guard let value = try container.decodeIfPresent(V.self, forKey: valueKey) else {
                return nil
            }
            // A stored value with a missing confidence decodes at zero rather
            // than defaulting to certainty. Absent evidence is not strong
            // evidence, and the phrasing layer keys off this number.
            let confidence = try container.decodeIfPresent(Double.self, forKey: confidenceKey) ?? 0
            return FrameAxis(value, confidence: confidence)
        }

        taper = try axis(.taper, .taperConfidence, as: FrameTaper.self)
        proportion = try axis(.proportion, .proportionConfidence, as: FrameProportion.self)
        scale = try axis(.scale, .scaleConfidence, as: FrameScale.self)
        muscularityHint = try container.decodeIfPresent(Double.self, forKey: .muscularityHint)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(taper?.value, forKey: .taper)
        try container.encodeIfPresent(taper?.confidence, forKey: .taperConfidence)
        try container.encodeIfPresent(proportion?.value, forKey: .proportion)
        try container.encodeIfPresent(proportion?.confidence, forKey: .proportionConfidence)
        try container.encodeIfPresent(scale?.value, forKey: .scale)
        try container.encodeIfPresent(scale?.confidence, forKey: .scaleConfidence)
        try container.encodeIfPresent(muscularityHint, forKey: .muscularityHint)
    }
}
