//
//  StylePreferenceInferenceTests.swift
//  AstraStyleTests
//
//  §6.9's inference: choices in, an eight-dimension vector out.
//
//  The cases that matter most here are the ones about what the inference REFUSES
//  to claim. A vector that reports eight confident numbers from three
//  photographs would pass every "does it produce output" test ever written, and
//  would be wrong in the one way nothing downstream can detect. So most of what
//  follows pins down absence, low confidence, and conflict — not the happy path.
//

import Foundation
import Testing
@testable import AstraStyle

private func pair(
    _ id: String,
    _ dimension: StyleDimension,
    aLoading: Double = 1.0,
    bLoading: Double = -1.0,
    extraOnA: [StyleDimension: Double] = [:]
) -> StyleQuizPair {
    func url(_ suffix: String) -> URL {
        // Never dereferenced by the inference — it works on loadings alone — but
        // `StyleQuizOption` will not exist without one, which is the point:
        // there is no way to construct an option whose imagery was not resolved.
        URL(fileURLWithPath: "/tmp/astra-quiz/\(id)-\(suffix).jpg")
    }
    return StyleQuizPair(
        id: id,
        optionA: StyleQuizOption(
            id: "a",
            imageName: "\(id)-a",
            imageURL: url("a"),
            accessibilityDescription: "Option A of \(id).",
            loadings: [dimension: aLoading].merging(extraOnA) { current, _ in current }
        ),
        optionB: StyleQuizOption(
            id: "b",
            imageName: "\(id)-b",
            imageURL: url("b"),
            accessibilityDescription: "Option B of \(id).",
            loadings: [dimension: bLoading]
        )
    )
}

private func answers(_ entries: [(String, String)]) -> [StylePreferenceQuizAnswer] {
    entries.map { StylePreferenceQuizAnswer(pairID: $0.0, chosenOptionID: $0.1) }
}

@Suite("Style quiz inference — what it will and will not claim")
struct StylePreferenceInferenceTests {

    // MARK: What it refuses to claim

    @Test("An axis nobody asked about has NO entry — not a neutral one")
    func unaskedAxesAreAbsent() {
        // The single most important property in this file. With the three
        // comparisons that exist, five of the eight axes come back absent. If
        // they came back as 0 they would be indistinguishable from a man who was
        // asked and landed exactly in the middle — and Style DNA would be built
        // from three measurements and five fabrications that look identical.
        let catalog = StyleQuizCatalog(pairs: [pair("f", .formality)])
        let vector = StylePreferenceInference.vector(
            from: answers([("f", "a")]),
            catalog: catalog,
            comparisonsOffered: 1
        )

        #expect(vector.dimensions.count == 1)
        for dimension in StyleDimension.allCases where dimension != .formality {
            #expect(vector.dimensions[dimension] == nil)
            #expect(vector.score(for: dimension) == nil)
            #expect(vector.confidence(for: dimension) == .insufficient)
        }
    }

    @Test("An axis asked about but passed on is present with no score")
    func passedAxisIsPresentButUnscored() {
        // Different from the case above, and the difference is actionable: "he
        // had no opinion" cannot be fixed by asking again, "we never asked" can.
        let catalog = StyleQuizCatalog(pairs: [pair("f", .formality)])
        let vector = StylePreferenceInference.vector(
            from: answers([("f", StyleQuizPair.noPreferenceOptionID)]),
            catalog: catalog,
            comparisonsOffered: 1
        )

        let reading = vector.dimensions[.formality]
        #expect(reading != nil)
        #expect(reading?.score == nil)
        #expect(reading?.observations == 0)
        #expect(reading?.confidence == .insufficient)
        // It still counts as answered — he did engage with the comparison.
        #expect(vector.comparisonsAnswered == 1)
        #expect(vector.isEmpty)
    }

    @Test("One comparison gives a direction at low confidence, never more")
    func oneComparisonIsLowConfidence() {
        let catalog = StyleQuizCatalog(pairs: [pair("f", .formality)])
        let vector = StylePreferenceInference.vector(
            from: answers([("f", "a")]),
            catalog: catalog,
            comparisonsOffered: 1
        )

        #expect(vector.score(for: .formality) == 1.0)
        // The score is ±1 because "he picked this one" is what a forced choice
        // means — not because he is at the extreme of the axis. The confidence is
        // what stops anything downstream reading it that way.
        #expect(vector.confidence(for: .formality) == .low)
        #expect(!vector.confidence(for: .formality).isStatable)
        #expect(vector.statableDimensions.isEmpty)
    }

    @Test("Conflicting answers lower confidence rather than averaging away")
    func conflictLowersConfidence() {
        // Four comparisons split two-two. The score is 0 — but so is the score
        // of a man with four consistent middling answers, and those two are not
        // the same person. `agreement` is what separates them.
        let catalog = StyleQuizCatalog(pairs: (1...4).map { pair("s-\($0)", .silhouette) })
        let vector = StylePreferenceInference.vector(
            from: answers([("s-1", "a"), ("s-2", "b"), ("s-3", "a"), ("s-4", "b")]),
            catalog: catalog,
            comparisonsOffered: 4
        )

        let reading = vector.dimensions[.silhouette]
        #expect(reading?.score == 0)
        #expect(reading?.observations == 4)
        #expect(reading?.agreement == 0)
        #expect(reading?.confidence == .low)
        #expect(vector.statableDimensions.isEmpty)
    }

    @Test("Three out of four one way is moderate, not high")
    func majorityIsModerate() {
        let catalog = StyleQuizCatalog(pairs: (1...4).map { pair("s-\($0)", .silhouette) })
        let vector = StylePreferenceInference.vector(
            from: answers([("s-1", "a"), ("s-2", "a"), ("s-3", "a"), ("s-4", "b")]),
            catalog: catalog,
            comparisonsOffered: 4
        )

        #expect(vector.score(for: .silhouette) == 0.5)
        #expect(vector.dimensions[.silhouette]?.agreement == 0.5)
        // A man who picked the loose cut three times out of four has told us
        // something, but not something to state back to him as a fact.
        #expect(vector.confidence(for: .silhouette) == .moderate)
    }

    @Test("Four consistent comparisons reach high confidence")
    func consistentRunReachesHigh() {
        let catalog = StyleQuizCatalog(pairs: (1...4).map { pair("s-\($0)", .silhouette) })
        let vector = StylePreferenceInference.vector(
            from: answers([("s-1", "a"), ("s-2", "a"), ("s-3", "a"), ("s-4", "a")]),
            catalog: catalog,
            comparisonsOffered: 4
        )

        #expect(vector.score(for: .silhouette) == 1.0)
        #expect(vector.confidence(for: .silhouette) == .high)
        #expect(vector.statableDimensions == [.silhouette])
    }
}

@Suite("Style quiz inference — partial runs, weighting and storage")
struct StylePreferenceInferenceEdgeCaseTests {

    @Test("Skipping the whole step produces a usable, empty vector")
    func skippingIsUsable() {
        // §6.9's step is skippable and skipping must not produce a broken
        // profile. `.skipped` is a real value with a real shape, not nil, so
        // every consumer takes one code path.
        let vector = StylePreferenceInference.vector(
            from: [],
            catalog: StyleQuizCatalog(pairs: [pair("f", .formality)]),
            comparisonsOffered: 1
        )

        #expect(vector.isEmpty)
        #expect(vector.comparisonsAnswered == 0)
        #expect(vector.comparisonsOffered == 1)
        #expect(vector.measuredDimensions.isEmpty)
        #expect(StylePreferenceVector.skipped.isEmpty)
    }

    @Test("Leaving part-way through scores what was answered and nothing else")
    func partialRunScoresOnlyWhatWasAnswered() {
        let catalog = StyleQuizCatalog(pairs: [
            pair("f", .formality),
            pair("c", .colourTolerance),
            pair("s", .silhouette)
        ])
        let vector = StylePreferenceInference.vector(
            from: answers([("f", "a")]),
            catalog: catalog,
            comparisonsOffered: 3
        )

        #expect(vector.measuredDimensions == [.formality])
        // Present-but-unmeasured, because the catalog COULD have asked. This is
        // what tells a later reader that the man left early rather than that the
        // build had no imagery for colour.
        #expect(vector.dimensions[.colourTolerance]?.score == nil)
        #expect(vector.dimensions[.silhouette]?.score == nil)
        #expect(vector.comparisonsAnswered == 1)
        #expect(vector.comparisonsOffered == 3)
    }

    @Test("A secondary loading counts for less than a primary one")
    func partialLoadingsCountProportionally() {
        // Two half-weight looks at an axis are worth one full-weight look. The
        // shipped pairs do not use secondary loadings — see the manifest README
        // for why — but the arithmetic has to be right before one does.
        let catalog = StyleQuizCatalog(pairs: [
            pair("f-1", .formality, extraOnA: [.contrastPreference: 0.5]),
            pair("f-2", .formality, extraOnA: [.contrastPreference: 0.5])
        ])
        let vector = StylePreferenceInference.vector(
            from: answers([("f-1", "a"), ("f-2", "a")]),
            catalog: catalog,
            comparisonsOffered: 2
        )

        #expect(vector.dimensions[.formality]?.observations == 2)
        #expect(vector.confidence(for: .formality) == .moderate)

        #expect(vector.dimensions[.contrastPreference]?.observations == 1)
        #expect(vector.score(for: .contrastPreference) == 1.0)
        // Same two taps, same direction, but half the evidence — so it stays low
        // while formality reaches moderate.
        #expect(vector.confidence(for: .contrastPreference) == .low)
    }

    @Test("An answer naming a pair the catalog lacks is skipped, not scored")
    func unknownPairsAreSkipped() {
        let catalog = StyleQuizCatalog(pairs: [pair("f", .formality)])
        let vector = StylePreferenceInference.vector(
            from: answers([("f", "a"), ("retired", "a")]),
            catalog: catalog,
            comparisonsOffered: 1
        )
        #expect(vector.comparisonsAnswered == 1)
        #expect(vector.dimensions[.formality]?.observations == 1)
    }

    @Test("Every score stays inside the -1…1 the sign conventions promise")
    func scoresStayInRange() {
        let catalog = StyleQuizCatalog(pairs: (1...9).map { pair("s-\($0)", .silhouette) })
        // Every combination of nine answers is more than needed; the extremes and
        // a scatter through the middle are the shape that could go out of range.
        for aCount in 0...9 {
            let given = (1...9).map { ("s-\($0)", $0 <= aCount ? "a" : "b") }
            let vector = StylePreferenceInference.vector(
                from: answers(given), catalog: catalog, comparisonsOffered: 9
            )
            let score = vector.score(for: .silhouette) ?? 0
            #expect(score >= -1 && score <= 1)
            let agreement = vector.dimensions[.silhouette]?.agreement ?? 0
            #expect(agreement >= 0 && agreement <= 1)
        }
    }

    @Test("The vector stores as a keyed jsonb object, not an alternating array")
    func vectorEncodesAsAKeyedObject() throws {
        // Swift's synthesised Codable encodes a dictionary with a non-String key
        // type as [key, value, key, value, …]. That is valid JSON, round-trips
        // through Swift perfectly, and is unreadable by the Edge Function and
        // unqueryable by `-> 'dimensions' ->> 'formality'`. The failure would only
        // ever be visible to a human looking at a stored row, which is why it is
        // pinned here.
        let catalog = StyleQuizCatalog(pairs: [pair("f", .formality)])
        let vector = StylePreferenceInference.vector(
            from: answers([("f", "a")]), catalog: catalog, comparisonsOffered: 1
        )

        let data = try JSONEncoder().encode(vector)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["comparisons_answered"] as? Int == 1)
        #expect(object["comparisons_offered"] as? Int == 1)

        let dimensions = try #require(object["dimensions"] as? [String: Any])
        let formality = try #require(dimensions["formality"] as? [String: Any])
        #expect(formality["score"] as? Double == 1.0)
        #expect(formality["confidence"] as? String == "low")

        let decoded = try JSONDecoder().decode(StylePreferenceVector.self, from: data)
        #expect(decoded == vector)
    }

    @Test("An unfamiliar axis in stored data is skipped, not fatal")
    func unknownStoredDimensionIsSkipped() throws {
        // A server that starts writing a ninth axis must not make an older client
        // unable to decode a user's own profile.
        let json = """
        {"version": 1, "comparisons_answered": 2, "comparisons_offered": 2, "dimensions": {\
        "formality": {"score": 1, "confidence": "moderate", "observations": 2, "agreement": 1},\
        "shoe_shape": {"score": 1, "confidence": "high", "observations": 4, "agreement": 1}}}
        """
        let decoded = try JSONDecoder().decode(StylePreferenceVector.self, from: Data(json.utf8))
        #expect(decoded.dimensions.count == 1)
        #expect(decoded.confidence(for: .formality) == .moderate)
    }

    @Test("The summary claims only as much as the confidence supports")
    func summaryMatchesConfidence() {
        let weak = StylePreferenceInference.vector(
            from: answers([("f", "a")]),
            catalog: StyleQuizCatalog(pairs: [pair("f", .formality)]),
            comparisonsOffered: 1
        )
        #expect(StylePreferenceInference.learnedSummary(for: weak).contains("first read"))

        let strongCatalog = StyleQuizCatalog(pairs: (1...4).map { pair("f-\($0)", .formality) })
        let strong = StylePreferenceInference.vector(
            from: answers([("f-1", "a"), ("f-2", "a"), ("f-3", "a"), ("f-4", "a")]),
            catalog: strongCatalog,
            comparisonsOffered: 4
        )
        #expect(StylePreferenceInference.learnedSummary(for: strong).contains("clear read"))

        let none = StylePreferenceInference.vector(
            from: answers([("f", StyleQuizPair.noPreferenceOptionID)]),
            catalog: StyleQuizCatalog(pairs: [pair("f", .formality)]),
            comparisonsOffered: 1
        )
        #expect(StylePreferenceInference.learnedSummary(for: none).contains("No strong pull"))
    }

    @Test("Tolerance bands round-trip through the 0-100 columns they are stored in")
    func toleranceBandsRoundTrip() {
        // `style_profiles.logo_tolerance` and `trend_tolerance` are smallint
        // 0-100, and Swift modelled them as a String enum until this ticket —
        // keys matching, values unstorable, and nothing failing until the first
        // non-nil write. The mapping now has exactly one home; this pins it.
        for level in ToleranceLevel.allCases {
            #expect(ToleranceLevel(score: level.score) == level)
            #expect(level.score >= 0 && level.score <= 100)
        }
        #expect(ToleranceLevel(score: -40) == .none)
        #expect(ToleranceLevel(score: 400) == .high)
    }
}
