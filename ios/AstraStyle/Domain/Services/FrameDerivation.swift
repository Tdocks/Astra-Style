//
//  FrameDerivation.swift
//  AstraStyle
//
//  Turns the measurements spec §6.6 collects into the three axes of
//  `FrameProfile`. Pure, synchronous and free of I/O so it can be exhaustively
//  unit-tested — this is the layer every downstream fit decision rests on, and
//  a quiet error here is invisible in the UI and wrong in every recommendation.
//
//  See `docs/14-frame-fit.md` §2.
//

import Foundation

public enum FrameDerivation {

    // MARK: - Entry point

    /// Derives the wearer's frame from their stored measurements.
    ///
    /// - Parameter body: The `body_profiles` row. Every field is optional by
    ///   design, and every measurement is in centimetres.
    /// - Returns: A profile whose axes are `nil` wherever the inputs did not
    ///   support a conclusion. Never throws; unusable input yields
    ///   `FrameProfile.unknown`, which every consumer already handles.
    ///
    /// There is deliberately **no `units:` parameter.** An earlier draft took
    /// one, on the assumption that `body_profiles` stored numbers in whatever
    /// `profiles.units` said. It does not: storage is canonically metric and
    /// `units` is a display preference (see BodyProfile.swift). A `units:`
    /// parameter would therefore be a live footgun — every caller would have to
    /// remember to pass `.metric` regardless of the user's setting, and the one
    /// who passed the user's actual preference would get a confident, entirely
    /// wrong frame with no error anywhere.
    public static func derive(from body: BodyProfile) -> FrameProfile {
        let measurements = Normalised(body: body)

        var profile = FrameProfile(
            taper: taper(from: measurements, body: body),
            proportion: proportion(from: measurements),
            scale: scale(from: measurements),
            muscularityHint: muscularityHint(from: measurements)
        )

        applyStatedFitIssues(body.fitNotes, to: &profile)
        return profile
    }

    // MARK: - Unit normalisation

    /// Measurements converted from the stored centimetres to inches, with
    /// implausible values discarded.
    ///
    /// The bands below are stated in inches on purpose. A "7 drop" is a real,
    /// named grade in tailoring; restating it as 17.78cm would obscure where
    /// the number comes from and make it look arbitrary to the next reader.
    ///
    /// The range checks are the second line of defence. They catch a value
    /// entered in inches into a centimetre field, a typo'd extra digit, and a
    /// field left at zero — each of which otherwise yields an authoritative
    /// frame that nobody can see is wrong.
    private struct Normalised {
        let height: Double?
        let chest: Double?
        let waist: Double?
        let inseam: Double?
        let neck: Double?
        let shirtSize: String?
        let trouserWaist: Double?

        init(body: BodyProfile) {
            // Plausible adult ranges in inches, generous at both ends. These are
            // not here to judge anybody — they are here to reject input that
            // cannot be a measurement.
            func inches(_ cm: Double?, _ range: ClosedRange<Double>) -> Double? {
                guard let converted = BodyProfile.inches(fromCm: cm) else { return nil }
                return range.contains(converted) ? converted : nil
            }

            height = inches(body.heightCm, 48...90)
            chest = inches(body.chestCm, 26...70)
            waist = inches(body.waistCm, 22...70)
            inseam = inches(body.inseamCm, 22...42)
            neck = inches(body.neckCm, 11...24)
            shirtSize = body.shirtSize?.trimmingCharacters(in: .whitespacesAndNewlines)

            // Trouser size is a free-text string ("32", "32x30", "W34 L32").
            // The leading number is the waist in inches by convention in every
            // market that uses lettered shirt sizes, so it is NOT unit-converted.
            trouserWaist = Self.leadingNumber(in: body.trouserSize)
                .flatMap { (22...70).contains($0) ? $0 : nil }
        }

        static func leadingNumber(in text: String?) -> Double? {
            guard let text else { return nil }
            let digits = text.prefix { $0.isNumber || $0 == "." }
            return digits.isEmpty ? nil : Double(digits)
        }
    }

    // MARK: - Taper (the tailoring drop)

    /// Chest minus waist. This is the number tailors actually grade suits by —
    /// 6" regular, 7–8" athletic, ≤4" straight — not an invented metric.
    private static func taper(
        from measurements: Normalised,
        body: BodyProfile
    ) -> FrameAxis<FrameTaper>? {
        if let chest = measurements.chest, let waist = measurements.waist {
            let drop = chest - waist

            // A waist larger than the chest is a legitimate measurement, not an
            // error — it reads as `straight`, confidently.
            let value: FrameTaper = switch drop {
            case 7...: .strong
            case 4.5..<7: .moderate
            default: .straight
            }

            // Confidence falls off near a band edge. A drop of 6.9" is not
            // meaningfully different from 7.1", and asserting "athletic" at one
            // and "regular" at the other would be false precision the user can
            // feel — he changes one number by a quarter inch and the advice flips.
            let distanceFromEdge = min(abs(drop - 7), abs(drop - 4.5))
            let confidence = 0.65 + 0.35 * min(distanceFromEdge / 2.0, 1)
            return FrameAxis(value, confidence: confidence)
        }

        // Fallback: shirt size against trouser waist. Coarse, but it is exactly
        // how most men discover they need an athletic cut in the first place —
        // a large shirt over a 32 waist is a real signal, and refusing to use
        // it because we lack a tape measure serves nobody.
        if let shirt = shirtChestEstimate(measurements.shirtSize), let trouser = measurements.trouserWaist {
            let drop = shirt - trouser
            let value: FrameTaper = switch drop {
            case 7...: .strong
            case 4.5..<7: .moderate
            default: .straight
            }
            // Capped low on purpose: lettered sizing varies enormously by brand
            // and market, so this must never speak with a tape measure's authority.
            return FrameAxis(value, confidence: 0.35)
        }

        return nil
    }

    /// Rough chest circumference in inches for a lettered shirt size.
    ///
    /// Deliberately conservative and deliberately incomplete. Returns `nil` for
    /// anything unrecognised rather than guessing, because a wrong estimate here
    /// is worse than no estimate: it produces a *confident* wrong taper, and the
    /// user has no way to see where it came from.
    private static func shirtChestEstimate(_ size: String?) -> Double? {
        guard let size = size?.lowercased() else { return nil }
        return switch size {
        case "xs", "x-small", "extra small": 34
        case "s", "small": 37
        case "m", "medium": 40
        case "l", "large": 43
        case "xl", "x-large", "extra large": 47
        case "xxl", "2xl", "xx-large": 51
        case "xxxl", "3xl": 55
        default: nil
        }
    }

    // MARK: - Proportion (leg length against height)

    private static func proportion(from measurements: Normalised) -> FrameAxis<FrameProportion>? {
        guard let height = measurements.height, let inseam = measurements.inseam else { return nil }

        // Guard the relationship as well as each value: an inseam longer than
        // 60% of height is anatomically impossible and means the two fields
        // were entered in different units or swapped.
        let ratio = inseam / height
        guard (0.35...0.58).contains(ratio) else { return nil }

        let value: FrameProportion = switch ratio {
        case 0.48...: .longLeg
        case 0.45..<0.48: .balanced
        default: .longTorso
        }

        let distanceFromEdge = min(abs(ratio - 0.48), abs(ratio - 0.45))
        let confidence = 0.7 + 0.3 * min(distanceFromEdge / 0.02, 1)
        return FrameAxis(value, confidence: confidence)
    }

    // MARK: - Scale

    private static func scale(from measurements: Normalised) -> FrameAxis<FrameScale>? {
        guard let height = measurements.height else { return nil }

        let value: FrameScale = switch height {
        case 73...: .tall        // 6'1" and over
        case 67..<73: .average   // 5'7" – 6'1"
        default: .compact
        }

        let distanceFromEdge = min(abs(height - 73), abs(height - 67))
        let confidence = 0.75 + 0.25 * min(distanceFromEdge / 2.0, 1)
        return FrameAxis(value, confidence: confidence)
    }

    // MARK: - Muscularity hint

    /// Neck against chest, mapped to roughly `0...1`.
    ///
    /// Two men with a 46" chest can carry very different amounts of muscle, and
    /// the one who carries more is the one whose clothes come under tension
    /// first. Weight would be the obvious input here and is deliberately unused
    /// — see `docs/14-frame-fit.md` §2. Neck is the least intrusive proxy we
    /// already collect, and unlike weight it says something specific about how
    /// a garment will sit.
    private static func muscularityHint(from measurements: Normalised) -> Double? {
        guard let neck = measurements.neck, let chest = measurements.chest, chest > 0 else { return nil }
        // Typical ratio runs about 0.33–0.38. Map that span onto 0...1 and clamp.
        let ratio = neck / chest
        return max(0, min(1, (ratio - 0.33) / 0.05))
    }

    // MARK: - Stated fit issues win

    /// Overrides derived axes with what the user actually told us.
    ///
    /// A stated fit issue outranks any derivation, at full confidence. He has
    /// stood in front of a mirror; we have divided two numbers. When they
    /// disagree, he is right — and an app that quietly overrules a man's own
    /// account of his body has failed at something more important than fit.
    private static func applyStatedFitIssues(
        _ issues: [FitIssue],
        to profile: inout FrameProfile
    ) {
        for issue in issues {
            switch issue {
            case .broadChest:
                profile.taper = FrameAxis(.strong, confidence: 1)
            case .narrowShoulders:
                profile.taper = FrameAxis(.straight, confidence: 1)
            case .shortTorso, .longLegs:
                profile.proportion = FrameAxis(.longLeg, confidence: 1)
            case .longTorso, .shortLegs:
                profile.proportion = FrameAxis(.longTorso, confidence: 1)
            case .tallFrame:
                profile.scale = FrameAxis(.tall, confidence: 1)
            case .shortFrame:
                profile.scale = FrameAxis(.compact, confidence: 1)
            case .largeThighs:
                // Not an axis — it is the canonical tension case, and
                // `FrameHarmonyScorer` reads it straight off `fitNotes`.
                // Forcing it into `taper` would misfile a leg fact as a
                // torso one and change advice about jackets.
                continue
            case .longArms, .shortArms, .other:
                continue
            }
        }
    }
}
