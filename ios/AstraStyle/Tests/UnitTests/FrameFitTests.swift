//
//  FrameFitTests.swift
//  AstraStyleTests
//
//  Frame-aware fit (docs/14-frame-fit.md).
//
//  The most important test in this file is the FIRST one. Everything else here
//  checks that a new feature works; that one checks that the overwhelming
//  majority of users — the ones who skipped the optional measurements step —
//  see scores identical to what they saw before the feature existed. That is
//  the regression that would ship silently, because it is invisible to anyone
//  testing with a filled-in profile.
//

import Foundation
import Testing
@testable import AstraStyle

// MARK: - Fixtures

private func item(
    category: ClothingCategory,
    fit: ItemFit? = nil,
    material: [String] = []
) -> ClosetItem {
    ClosetItem(
        id: UUID(),
        userID: UUID(),
        name: "Test garment",
        category: category,
        material: material,
        fit: fit
    )
}

/// Takes INCHES and stores centimetres, because `body_profiles` is canonically
/// metric while the tailoring bands under test are stated in inches. Writing
/// the fixtures in inches keeps each case readable as a real man's
/// measurements — a 44" chest over a 34" waist is recognisably athletic, and
/// 111.8 over 86.4 is not — while still exercising the cm storage path the app
/// actually uses.
private func body(
    heightIn: Double? = nil,
    chestIn: Double? = nil,
    waistIn: Double? = nil,
    inseamIn: Double? = nil,
    neckIn: Double? = nil,
    shirtSize: String? = nil,
    trouserSize: String? = nil,
    fitNotes: [FitIssue] = []
) -> BodyProfile {
    func cm(_ inches: Double?) -> Double? { inches.map { $0 * 2.54 } }
    return BodyProfile(
        userID: UUID(),
        heightCm: cm(heightIn),
        chestCm: cm(chestIn),
        waistCm: cm(waistIn),
        inseamCm: cm(inseamIn),
        neckCm: cm(neckIn),
        shirtSize: shirtSize,
        trouserSize: trouserSize,
        fitNotes: fitNotes
    )
}

/// Stores raw centimetre values without conversion, for the cases that are
/// specifically about what the column contains.
private func bodyCm(
    heightCm: Double? = nil,
    chestCm: Double? = nil,
    waistCm: Double? = nil,
    inseamCm: Double? = nil
) -> BodyProfile {
    BodyProfile(
        userID: UUID(),
        heightCm: heightCm,
        chestCm: chestCm,
        waistCm: waistCm,
        inseamCm: inseamCm
    )
}

// MARK: - The regression that matters

@Suite("Frame fit — no measurements reproduces pre-frame behaviour")
struct FrameFitNoRegressionTests {

    @Test("An empty body profile derives no axes at all")
    func emptyBodyYieldsUnknownFrame() {
        let frame = FrameDerivation.derive(from: body())
        #expect(frame.isEmpty)
        #expect(frame.overallConfidence == 0)
    }

    @Test("An unknown frame makes the scorer contribute nothing")
    func unknownFrameIsUninformative() {
        let result = FrameHarmonyScorer.score(
            item: item(category: .bottom, fit: .slim, material: ["selvedge denim"]),
            frame: .unknown
        )
        #expect(result.isUninformative)
        #expect(result.reasons.isEmpty)
    }

    @Test("With no frame harmony, the composite equals the pre-split score exactly")
    func compositeUnchangedWithoutFrame() {
        // Deliberately asymmetric values: if the blend leaked in at any share,
        // uniform inputs would hide it.
        let breakdown = CompatibilityBreakdown(
            colorCompatibility: 0.8, formalityAlignment: 0.6,
            silhouetteCompatibility: 0.4,
            seasonWeatherSuitability: 0.9, userPreference: 0.7,
            historicalCoWear: 0.5, occasionRelevance: 0.3, availabilityLaundry: 1.0
        )
        #expect(breakdown.frameHarmony == nil)
        #expect(breakdown.silhouetteCompatibility == 0.4)

        // The value spec §10's formula produces for these inputs.
        let expected = 0.8 * 0.25 + 0.6 * 0.20 + 0.4 * 0.15 + 0.9 * 0.10
            + 0.7 * 0.10 + 0.5 * 0.10 + 0.3 * 0.05 + 1.0 * 0.05
        #expect(breakdown.score() == Int((expected * 100).rounded()))
    }

    @Test("Frame harmony changes the composite only when present")
    func frameHarmonyMovesTheScoreWhenKnown() {
        let without = CompatibilityBreakdown(
            colorCompatibility: 0.5, formalityAlignment: 0.5,
            silhouetteCompatibility: 0.5,
            seasonWeatherSuitability: 0.5, userPreference: 0.5,
            historicalCoWear: 0.5, occasionRelevance: 0.5, availabilityLaundry: 0.5
        )
        let with = CompatibilityBreakdown(
            colorCompatibility: 0.5, formalityAlignment: 0.5,
            silhouetteCompatibility: 0.5, frameHarmony: 0.0,
            seasonWeatherSuitability: 0.5, userPreference: 0.5,
            historicalCoWear: 0.5, occasionRelevance: 0.5, availabilityLaundry: 0.5
        )
        #expect(with.score() < without.score())

        // The design ceiling: 0.45 of the 0.15 silhouette weight is ~6.75
        // points of 100. Frame fit must be able to break a tie and must not be
        // able to overrule colour, occasion, or a stated preference.
        #expect(without.score() - with.score() <= 7)
    }
}

// MARK: - Derivation

@Suite("Frame fit — derivation")
struct FrameDerivationTests {

    @Test("A 7-inch drop grades as athletic")
    func athleticDrop() {
        let frame = FrameDerivation.derive(
            from: body(chestIn: 44, waistIn: 34)
        )
        #expect(frame.taper?.value == .strong)
    }

    @Test("A 4-inch drop grades as straight")
    func straightDrop() {
        let frame = FrameDerivation.derive(
            from: body(chestIn: 40, waistIn: 36)
        )
        #expect(frame.taper?.value == .straight)
    }

    @Test("Confidence drops near a band edge rather than flipping crisply")
    func confidenceFallsOffAtBandEdges() {
        let borderline = FrameDerivation.derive(
            from: body(chestIn: 44, waistIn: 37.1)   // drop 6.9
        )
        let clear = FrameDerivation.derive(
            from: body(chestIn: 46, waistIn: 32)     // drop 14
        )
        #expect(borderline.taper!.confidence < clear.taper!.confidence)
    }

    /// `body_profiles` stores centimetres canonically, so the derivation is
    /// unconditional cm→inches. The failure this guards is the inverse of the
    /// one originally anticipated: somebody entering INCHES into a centimetre
    /// column. That has to yield nothing, not a plausible-looking frame.
    @Test("Centimetres are read as centimetres")
    func centimetresAreConverted() {
        // 111.8cm chest / 86.4cm waist == 44" / 34" == a 10" drop, athletic.
        let stored = bodyCm(chestCm: 111.8, waistCm: 86.4)
        #expect(FrameDerivation.derive(from: stored).taper?.value == .strong)
    }

    @Test("Inches typed into a centimetre column produce no conclusion at all")
    func inchesInACentimetreColumnAreRejected() {
        // 44 and 34 are a real man's chest and waist in INCHES. Read as
        // centimetres — which is what the column means — they are 17.3" and
        // 13.4", outside any plausible adult range. The right answer is
        // silence: a 4-inch "drop" derived from these would look entirely
        // reasonable in the output and be built on nothing.
        let mistyped = bodyCm(heightCm: 71, chestCm: 44, waistCm: 34, inseamCm: 32)
        let frame = FrameDerivation.derive(from: mistyped)
        #expect(frame.isEmpty)
    }

    @Test("Implausible values yield no axis rather than a confident wrong one")
    func implausibleValuesAreDiscarded() {
        // An inseam longer than the height: transposed fields.
        let transposed = FrameDerivation.derive(
            from: body(heightIn: 32, inseamIn: 70)
        )
        #expect(transposed.proportion == nil)

        // A zero is "not answered", not "zero inches".
        let zeroed = FrameDerivation.derive(
            from: body(heightIn: 0, chestIn: 0, waistIn: 0)
        )
        #expect(zeroed.isEmpty)
    }

    @Test("Sizes alone give a coarse taper at deliberately low confidence")
    func sizeFallback() {
        let frame = FrameDerivation.derive(
            from: body(shirtSize: "L", trouserSize: "32")
        )
        #expect(frame.taper?.value == .strong)
        // Lettered sizing varies enormously by brand; this must never speak
        // with a tape measure's authority.
        #expect(frame.taper!.confidence < FrameHarmonyScorer.assertionThreshold)
    }

    @Test("An unrecognised shirt size yields nothing rather than a guess")
    func unknownShirtSizeIsNotGuessed() {
        let frame = FrameDerivation.derive(
            from: body(shirtSize: "Athletic Fit 16.5/34", trouserSize: "32")
        )
        #expect(frame.taper == nil)
    }

    @Test("A stated fit issue overrides a contradicting derived axis, at full confidence")
    func statedFitIssueWins() {
        // The measurements say straight; the user says broad chest. He is right.
        let frame = FrameDerivation.derive(
            from: body(chestIn: 40, waistIn: 38, fitNotes: [.broadChest])
        )
        #expect(frame.taper?.value == .strong)
        #expect(frame.taper?.confidence == 1)
    }

    @Test("largeThighs is not filed into a torso axis")
    func largeThighsDoesNotBecomeTaper() {
        // It is a fact about legs. Mapping it to taper would silently turn it
        // into advice about jackets.
        let frame = FrameDerivation.derive(
            from: body(fitNotes: [.largeThighs])
        )
        #expect(frame.taper == nil)
        #expect(frame.isEmpty)
    }
}

// MARK: - The skinny-jeans case

@Suite("Frame fit — fabric decides the tension case, not width")
struct FrameFitTensionTests {

    private let thighs: [FitIssue] = [.largeThighs]

    @Test("Rigid cloth cut slim is penalised")
    func rigidSlimIsPenalised() {
        let result = FrameHarmonyScorer.score(
            item: item(category: .bottom, fit: .slim, material: ["100% cotton selvedge denim"]),
            frame: .unknown,
            statedFitIssues: thighs
        )
        #expect(!result.isUninformative)
        #expect(result.score < FrameHarmonyScorer.neutral)
    }

    /// The point of the whole design. The received rule bans the silhouette;
    /// the optical rule bans the *strain*. Same nominal cut, opposite verdict.
    @Test("The same slim cut in cloth that gives is rewarded, not banned")
    func givingSlimIsRewarded() {
        let result = FrameHarmonyScorer.score(
            item: item(category: .bottom, fit: .slim, material: ["98% cotton", "2% elastane"]),
            frame: .unknown,
            statedFitIssues: thighs
        )
        #expect(!result.isUninformative)
        #expect(result.score > FrameHarmonyScorer.neutral)
    }

    @Test("Give wins over rigidity when both markers are present")
    func stretchDenimIsNotRigid() {
        // "Stretch selvedge denim" is a stretch fabric. The elastane governs
        // how it moves, and reading it as rigid would penalise exactly the
        // garment that solves the problem.
        let stretchy = item(
            category: .bottom, fit: .slim, material: ["stretch selvedge denim"]
        )
        #expect(FrameHarmonyScorer.behaviour(of: stretchy) == .gives)
    }

    @Test("An unrecorded fabric never fires a fabric-dependent rule")
    func unknownFabricIsNotPenalised() {
        // Most of a scanned closet has no composition recorded. Defaulting to
        // rigid so the penalty fires more often would present a guess as a
        // judgement.
        let result = FrameHarmonyScorer.score(
            item: item(category: .bottom, fit: .slim),
            frame: .unknown,
            statedFitIssues: thighs
        )
        #expect(result.isUninformative)
    }
}

// MARK: - Tone and confidence

@Suite("Frame fit — phrasing follows confidence")
struct FrameFitPhrasingTests {

    @Test("Low confidence offers a suggestion; high confidence states a reason")
    func hedgingFollowsConfidence() {
        let garment = item(category: .bottom, fit: .relaxed)

        let confident = FrameProfile(proportion: FrameAxis(.longTorso, confidence: 0.95))
        let unsure = FrameProfile(proportion: FrameAxis(.longTorso, confidence: 0.3))

        let confidentReasons = FrameHarmonyScorer.score(item: garment, frame: confident).reasons
        let unsureReasons = FrameHarmonyScorer.score(item: garment, frame: unsure).reasons

        #expect(!confidentReasons.isEmpty)
        // The hedged voice must actually be REACHABLE. The first implementation
        // thresholded mentions on `delta × confidence`, which meant a strong
        // rule at low confidence produced no output at all — so `suggestion`
        // was dead code for precisely the users it was written for, and the
        // app fell silent exactly where it should have been tentative.
        #expect(!unsureReasons.isEmpty)
        #expect(confidentReasons != unsureReasons)
    }

    @Test("Below the confidence floor a rule says nothing, not even hedged")
    func veryLowConfidenceSaysNothing() {
        let barelyKnown = FrameProfile(proportion: FrameAxis(.longTorso, confidence: 0.1))
        let result = FrameHarmonyScorer.score(
            item: item(category: .bottom, fit: .relaxed), frame: barelyKnown
        )
        // The score may still shift fractionally; the user is told nothing,
        // because "this might apply" is not information.
        #expect(result.reasons.isEmpty)
    }

    /// `check_ui_conventions.py` scans source lines. This asserts the same
    /// guarantee against the rule data itself, so a string assembled at runtime
    /// or moved out of a literal cannot slip past the source scan.
    @Test("No rule string makes the wearer's body the subject")
    func noRuleShamesTheWearer() {
        let banned = [
            "flatter", "your build", "your body", "your figure", "your frame",
            "slimming", "hide your", "conceal", "disguise", "despite your",
            "for someone your"
        ]
        for rule in FitRuleTable.all {
            for text in [rule.reason, rule.suggestion] {
                let lowered = text.lowercased()
                for phrase in banned {
                    #expect(
                        !lowered.contains(phrase),
                        "Rule \(rule.id) contains banned phrase '\(phrase)': \(text)"
                    )
                }
            }
        }
    }

    @Test("Every rule carries both an assertive and a hedged phrasing")
    func everyRuleHasBothVoices() {
        for rule in FitRuleTable.all {
            #expect(!rule.reason.isEmpty, "Rule \(rule.id) has no reason")
            #expect(!rule.suggestion.isEmpty, "Rule \(rule.id) has no suggestion")
        }
    }

    @Test("Rule ids are unique")
    func ruleIDsAreUnique() {
        let ids = FitRuleTable.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

// MARK: - Convention expiry

@Suite("Frame fit — convention rules expire, optical rules do not")
struct FitRuleBasisTests {

    private var farFuture: Date {
        DateComponents(calendar: .current, year: 2099, month: 1, day: 1).date!
    }

    @Test("Optical rules still fire in the far future")
    func opticalRulesDoNotExpire() {
        let active = FitRuleTable.active(on: farFuture)
        let optical = FitRuleTable.all.filter { $0.basis == .optical }
        #expect(!optical.isEmpty)
        #expect(active.count == optical.count)
    }

    @Test("Convention rules stop firing past their review date")
    func conventionRulesExpire() {
        let conventionRules = FitRuleTable.all.filter { $0.basis != .optical }
        #expect(!conventionRules.isEmpty, "The table should exercise both bases")
        #expect(FitRuleTable.active(on: farFuture).allSatisfy { $0.basis == .optical })
    }

    @Test("Convention carries less weight than geometry even while it is live")
    func conventionIsWeightedLower() {
        #expect(FitRuleBasis.optical.weightMultiplier > 1 - 0.0001)
        #expect(
            FitRuleBasis.convention(reviewAfter: DateComponents(year: 2029))
                .weightMultiplier < FitRuleBasis.optical.weightMultiplier
        )
    }
}

// MARK: - Ranking, not filtering

@Suite("Frame fit — ranks, never filters")
struct FrameFitRankingTests {

    @Test("The worst possible frame score still leaves an outfit recommendable")
    func frameCannotVetoAnOutfit() {
        // A garment the frame rules hate, everything else strong. It must still
        // score well: a bad ranking costs a slightly worse suggestion, while a
        // veto makes something the user owns and likes vanish from an app whose
        // whole job is to use what he already has.
        let hated = CompatibilityBreakdown(
            colorCompatibility: 1, formalityAlignment: 1,
            silhouetteCompatibility: 1, frameHarmony: 0,
            seasonWeatherSuitability: 1, userPreference: 1,
            historicalCoWear: 1, occasionRelevance: 1, availabilityLaundry: 1
        )
        #expect(hated.score() >= 93)
    }

    @Test("Frame harmony is bounded to 0...1 even when many rules stack")
    func scoreStaysBounded() {
        let frame = FrameProfile(
            taper: FrameAxis(.strong, confidence: 1),
            proportion: FrameAxis(.longTorso, confidence: 1),
            scale: FrameAxis(.compact, confidence: 1)
        )
        for category in ClothingCategory.allCases {
            for fit in ItemFit.allCases {
                let result = FrameHarmonyScorer.score(
                    item: item(category: category, fit: fit, material: ["selvedge denim"]),
                    frame: frame,
                    statedFitIssues: [.largeThighs]
                )
                #expect(result.score >= 0 && result.score <= 1)
            }
        }
    }

    @Test("An outfit score ignores garments no rule speaks to")
    func uninformativeGarmentsDoNotDragTheMean() {
        let frame = FrameProfile(proportion: FrameAxis(.longTorso, confidence: 0.9))
        let tapered = item(category: .bottom, fit: .slim)
        let fragrance = item(category: .fragrance)

        let alone = FrameHarmonyScorer.score(items: [tapered], frame: frame)
        let padded = FrameHarmonyScorer.score(items: [tapered, fragrance], frame: frame)

        #expect(!alone.isUninformative)
        #expect(alone.score == padded.score)
    }
}
