//
//  StyleDNADecodingTests.swift
//  AstraStyleTests
//
//  A CONTRACT test, not a round-trip test. The JSON literals below are copied
//  from what `supabase/functions/style-dna/` actually emits — including the
//  timestamp format — rather than produced by encoding a Swift value and
//  decoding it again. A round-trip test passes no matter what the keys are,
//  because both halves agree by construction; it would not have caught the
//  `BodyProfile` coding-key bug either (see that file's header), and it would
//  not catch this one:
//
//  `AstraAPIClient` sets `dateDecodingStrategy = .iso8601`, which is
//  `ISO8601DateFormatter` with DEFAULT options and therefore REJECTS
//  fractional seconds. Postgres `timestamptz` has microsecond precision. The
//  Edge Function normalizes to whole seconds in `_shared/time.ts` precisely
//  so this decode works; the test below pins that, so removing the
//  normalization fails here instead of on a device.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Style DNA response decoding")
struct StyleDNADecodingTests {

    /// The client's own decoder, configured exactly as `AstraAPIClient`
    /// configures it. Constructed here rather than shared so this test proves
    /// something about the real decode path and not about a lenient one
    /// written for the test's convenience.
    private static func apiDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Verbatim output of `POST /style-dna/generate` for a profile with an
    /// identity, a dress code, a week and three measured preference axes.
    private static let richResponseJSON = """
    {
      "primary_identity": "modern_heritage",
      "identity_basis": "the identity you ranked first",
      "secondary_influences": ["rugged_utility"],
      "palette": {
        "preferred_colors": ["charcoal", "navy", "oatmeal", "tobacco brown", "olive"],
        "avoided_colors": ["neon brights", "cold silver grey"],
        "rationale": "Modern Heritage runs on earth tones with one cold anchor."
      },
      "silhouette": {
        "headline": "Straight and substantial, with a natural shoulder.",
        "detail": "Heavier cloth holds its own shape, so a straight-leg trouser and an unpadded shoulder let it hang the way it was cut."
      },
      "signature_opportunities": [
        {
          "title": "A waxed cotton jacket in olive or brown",
          "reason": "It is the one layer that anchors this whole direction."
        }
      ],
      "wardrobe_priorities": [
        {
          "rank": 1,
          "title": "Cover the days you actually dress for",
          "reason": "You said your week is \\"Mostly in an office\\" with a business casual dress code."
        }
      ],
      "summary": "You are Modern Heritage.",
      "formality_preference": "formal",
      "logo_tolerance": 20,
      "trend_tolerance": 30,
      "accessory_preference": "moderate",
      "known_inputs": ["the style identities you picked", "your work dress code"],
      "open_questions": ["Kyra has not asked you about texture yet."],
      "measured_dimensions": ["colour_tolerance", "formality", "silhouette"],
      "generated_at": "2026-07-30T12:00:00Z",
      "model_identifier": "astra-deterministic-stylist/1"
    }
    """

    @Test("A full response decodes into all six §6.10 sections")
    func fullResponseDecodes() throws {
        let dna = try Self.apiDecoder().decode(
            StyleDNA.self,
            from: Data(Self.richResponseJSON.utf8)
        )

        #expect(dna.primaryIdentity == .modernHeritage)               // §6.10 primary identity
        #expect(dna.secondaryInfluences == [.ruggedUtility])          // §6.10 secondary influences
        #expect(dna.palette.preferredColors.count == 5)               // §6.10 preferred palette
        #expect(dna.palette.avoidedColors.contains("neon brights"))
        #expect(!dna.silhouette.headline.isEmpty)                     // §6.10 silhouette direction
        #expect(dna.signatureOpportunities.count == 1)                // §6.10 signature items
        #expect(dna.wardrobePriorities.first?.rank == 1)              // §6.10 wardrobe priorities

        // The four summary columns the endpoint owns, mapped onto the same
        // types `StyleProfile` uses for them.
        #expect(dna.formalityPreference == .formal)
        #expect(dna.logoTolerance == 20)
        #expect(dna.trendTolerance == 30)
        #expect(dna.accessoryPreference == .moderate)
        #expect(ToleranceLevel(score: 20) == .low)

        #expect(dna.measuredDimensions == ["colour_tolerance", "formality", "silhouette"])
        #expect(dna.modelIdentifier == "astra-deterministic-stylist/1")
        #expect(!dna.needsMoreInput)
        #expect(!dna.identityWasInferred)
    }

    @Test("The server's whole-second timestamp decodes under the client's .iso8601 strategy")
    func timestampDecodes() throws {
        let dna = try Self.apiDecoder().decode(
            StyleDNA.self,
            from: Data(Self.richResponseJSON.utf8)
        )
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 30
        components.hour = 12
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let expected = try #require(Calendar(identifier: .gregorian).date(from: components))
        #expect(dna.generatedAt == expected)
    }

    @Test("A sparse response decodes and reports what it does not know")
    func sparseResponseDecodes() throws {
        // Exactly what the endpoint returns for a profile with only §6.5
        // answered — the sparse case is the normal one while five of the
        // eight §6.9 dimensions have no imagery.
        let json = """
        {
          "primary_identity": "quiet_luxury",
          "identity_basis": "the identity you ranked first",
          "secondary_influences": ["minimalist", "executive"],
          "palette": {
            "preferred_colors": ["charcoal", "ivory", "camel", "navy", "stone grey"],
            "avoided_colors": ["bright primaries", "high-shine metallics"],
            "rationale": "Quiet Luxury runs on five neutrals that all sit together."
          },
          "silhouette": {
            "headline": "One unbroken column, cut close but never tight.",
            "detail": "This is the direction's own proportion; a measurement or two would make it specific to you."
          },
          "signature_opportunities": [
            { "title": "A fine-gauge crew knit in camel or ivory", "reason": "The single piece this direction is built on." }
          ],
          "wardrobe_priorities": [
            { "rank": 1, "title": "Fewer pieces, better cloth", "reason": "This direction shows fabric quality more than any other." }
          ],
          "summary": "You are Quiet Luxury.",
          "formality_preference": "formal",
          "logo_tolerance": 5,
          "trend_tolerance": 20,
          "accessory_preference": "minimal",
          "known_inputs": ["the style identities you picked"],
          "open_questions": [
            "What you wear to work. It decides how much of this wardrobe has to be work clothes.",
            "A chest and a waist measurement."
          ],
          "measured_dimensions": [],
          "generated_at": "2026-07-30T12:00:00Z",
          "model_identifier": "astra-deterministic-stylist/1"
        }
        """

        let dna = try Self.apiDecoder().decode(StyleDNA.self, from: Data(json.utf8))

        #expect(dna.primaryIdentity == .quietLuxury)
        #expect(!dna.signatureOpportunities.isEmpty)
        // Nothing was measured, so nothing is claimed as measured — and the
        // result says what would change that.
        #expect(dna.measuredDimensions.isEmpty)
        #expect(dna.openQuestions.count == 2)
        #expect(dna.knownInputs.count == 1)
    }

    @Test("A null identity decodes as the honest empty state, not a failure")
    func nullIdentityDecodes() throws {
        let json = """
        {
          "primary_identity": null,
          "identity_basis": "nothing yet — the identity step and the dress code question are both unanswered",
          "secondary_influences": [],
          "palette": { "preferred_colors": [], "avoided_colors": [], "rationale": "There is no palette yet." },
          "silhouette": { "headline": "Not enough to call yet.", "detail": "Cut advice needs a direction or a measurement." },
          "signature_opportunities": [],
          "wardrobe_priorities": [],
          "summary": "There is not enough here yet to call a direction.",
          "formality_preference": "balanced",
          "logo_tolerance": 25,
          "trend_tolerance": 40,
          "accessory_preference": "moderate",
          "known_inputs": [],
          "open_questions": ["Which three style identities look like you."],
          "measured_dimensions": [],
          "generated_at": "2026-07-30T12:00:00Z",
          "model_identifier": "astra-deterministic-stylist/1"
        }
        """

        let dna = try Self.apiDecoder().decode(StyleDNA.self, from: Data(json.utf8))
        #expect(dna.primaryIdentity == nil)
        #expect(dna.needsMoreInput)
        #expect(!dna.summary.isEmpty)
        #expect(!dna.openQuestions.isEmpty)
    }

    @Test("An inferred identity is distinguishable from a chosen one")
    func inferredIdentityIsFlagged() throws {
        let json = """
        {
          "primary_identity": "executive",
          "identity_basis": "your business formal dress code — the identity step has not been answered, so this is a starting point rather than your choice",
          "secondary_influences": ["quiet_luxury", "minimalist"],
          "palette": { "preferred_colors": ["navy"], "avoided_colors": ["neon brights"], "rationale": "A suiting palette." },
          "silhouette": { "headline": "Cut close through the waist.", "detail": "Tailoring reads well when it fits." },
          "signature_opportunities": [{ "title": "A navy suit", "reason": "It doubles as separates." }],
          "wardrobe_priorities": [{ "rank": 1, "title": "One suit that fits", "reason": "Alteration is part of the price." }],
          "summary": "Starting from Executive.",
          "formality_preference": "very_formal",
          "logo_tolerance": 5,
          "trend_tolerance": 20,
          "accessory_preference": "minimal",
          "known_inputs": ["your work dress code"],
          "open_questions": ["Which three style identities look like you."],
          "measured_dimensions": [],
          "generated_at": "2026-07-30T12:00:00Z",
          "model_identifier": "astra-deterministic-stylist/1"
        }
        """

        let dna = try Self.apiDecoder().decode(StyleDNA.self, from: Data(json.utf8))
        #expect(dna.primaryIdentity == .executive)
        // The screen must not present a guess in the same voice as a choice.
        #expect(dna.identityWasInferred)
    }

    @Test("An unknown secondary influence is skipped rather than failing the whole decode")
    func unknownIdentityIsSkipped() throws {
        // A newer server naming an eleventh identity must not blank the
        // result screen for everyone on an older build — the same
        // forward-compatibility rule as StylePreferenceVector.init(from:).
        let json = """
        {
          "primary_identity": "creative",
          "identity_basis": "the identity you ranked first",
          "secondary_influences": ["minimalist", "gorpcore"],
          "palette": { "preferred_colors": ["black"], "avoided_colors": [], "rationale": "Black holds it in place." },
          "silhouette": { "headline": "Deliberate mismatch.", "detail": "One strong shape at a time." },
          "signature_opportunities": [],
          "wardrobe_priorities": [],
          "summary": "You are Creative.",
          "formality_preference": "casual",
          "logo_tolerance": 35,
          "trend_tolerance": 70,
          "accessory_preference": "bold",
          "known_inputs": [],
          "open_questions": [],
          "measured_dimensions": [],
          "generated_at": "2026-07-30T12:00:00Z",
          "model_identifier": "astra-deterministic-stylist/1"
        }
        """

        let dna = try Self.apiDecoder().decode(StyleDNA.self, from: Data(json.utf8))
        #expect(dna.secondaryInfluences == [.minimalist])
    }

    @Test("A response missing a future field still decodes")
    func missingFieldsDecode() throws {
        // The minimum a client must survive: an older build reading a
        // response whose shape has moved on, or a partial projection.
        let json = """
        { "primary_identity": "minimalist", "summary": "You are Minimalist." }
        """
        let dna = try Self.apiDecoder().decode(StyleDNA.self, from: Data(json.utf8))
        #expect(dna.primaryIdentity == .minimalist)
        #expect(dna.palette.preferredColors.isEmpty)
        #expect(dna.wardrobePriorities.isEmpty)
        #expect(dna.knownInputs.isEmpty)
    }

    @Test("Applying the summary touches only the columns the endpoint owns")
    func applyingSummaryLeavesUserAnswersAlone() throws {
        let vector = StylePreferenceVector(
            comparisonsAnswered: 3,
            comparisonsOffered: 3,
            dimensions: [
                .formality: StyleDimensionReading(
                    score: 0.6, confidence: .moderate, observations: 2, agreement: 1
                )
            ]
        )
        let stored = StyleProfile(
            userID: UUID(),
            primaryIdentity: .ruggedUtility,
            secondaryIdentities: [.modernHeritage],
            styleGoals: ["build_complete_wardrobe"],
            preferredFit: .relaxed,
            preferenceVector: vector
        )

        let dna = try Self.apiDecoder().decode(
            StyleDNA.self,
            from: Data(Self.richResponseJSON.utf8)
        )
        let updated = dna.applyingSummary(to: stored)

        // The generator's output landed.
        #expect(updated.formalityPreference == .formal)
        #expect(updated.logoTolerance == 20)
        #expect(updated.preferredColors == dna.palette.preferredColors)
        #expect(updated.styleSummary == dna.summary)

        // The user's own answers did not move. A generator that wrote back
        // over its inputs would slowly overwrite what he actually said —
        // the rule 20260730180000_style_preference_vector.sql sets out.
        #expect(updated.primaryIdentity == .ruggedUtility)
        #expect(updated.secondaryIdentities == [.modernHeritage])
        #expect(updated.styleGoals == ["build_complete_wardrobe"])
        #expect(updated.preferredFit == .relaxed)
        #expect(updated.preferenceVector == vector)
    }
}
