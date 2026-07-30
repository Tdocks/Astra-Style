//
//  StyleQuizEngineTests.swift
//  AstraStyleTests
//
//  The §6.9 quiz's catalog loading and sequencing.
//
//  Two things here are worth more than the rest. The first is that a manifest
//  entry whose imagery is missing is DROPPED — the feature ships against three
//  pairs out of a specified twelve to twenty, and the property that makes that
//  honest instead of broken is that a stanza without photographs never becomes a
//  question. The second is coverage ordering: a badly ordered quiz still looks
//  like a working quiz, so nothing but a test will catch it.
//

import Foundation
import Testing
@testable import AstraStyle

// MARK: - Fixtures

/// Builds a manifest in memory so these tests never depend on which imagery
/// happens to be in the bundle this week — the comparison set is content, and a
/// test that asserts against today's content fails the day content is added.
private func manifest(_ pairs: [(id: String, priority: Int?, loadings: [(String, Double)])]) -> Data {
    func option(_ suffix: String, _ pairID: String, _ loadings: [(String, Double)], sign: Double) -> [String: Any] {
        var map: [String: Double] = [:]
        for (dimension, weight) in loadings { map[dimension] = weight * sign }
        return [
            "id": suffix,
            "image": "img-\(pairID)-\(suffix)",
            "accessibility_description": "A described outfit for \(pairID) \(suffix).",
            "loadings": map,
        ]
    }

    var entries: [[String: Any]] = []
    for pair in pairs {
        var entry: [String: Any] = [
            "id": pair.id,
            "option_a": option("a", pair.id, pair.loadings, sign: 1),
            "option_b": option("b", pair.id, pair.loadings, sign: -1),
        ]
        if let priority = pair.priority { entry["priority"] = priority }
        entries.append(entry)
    }

    let document: [String: Any] = ["version": 1, "pairs": entries]
    // Falling back to empty rather than force-trying: a serialisation failure
    // here surfaces as `load` throwing `unreadableManifest`, which fails the
    // calling test with a readable message instead of trapping the whole suite.
    return (try? JSONSerialization.data(withJSONObject: document)) ?? Data()
}

private func catalog(
    _ pairs: [(id: String, priority: Int?, loadings: [(String, Double)])],
    available: Set<String>? = nil
) throws -> StyleQuizCatalog {
    let data = manifest(pairs)
    if let available {
        return try StyleQuizCatalog.load(
            manifestData: data,
            locator: FixedStyleQuizImageLocator(available: available)
        )
    }
    return try StyleQuizCatalog.load(manifestData: data, locator: AlwaysResolvingImageLocator())
}

// MARK: - Loading

@Suite("Style quiz — the catalog only admits comparisons it can actually ask")
struct StyleQuizCatalogTests {

    @Test("A pair whose imagery is missing is dropped, with a reason")
    func missingImageryDropsThePair() throws {
        // The exact situation this feature ships in: a manifest describing more
        // comparisons than there are photographs. The pair must not become a
        // question backed by a placeholder — a placeholder gets answered like a
        // real photograph and the answer is recorded as a real preference.
        let loaded = try catalog(
            [
                ("formality-01", nil, [("formality", 1.0)]),
                ("texture-01", nil, [("texture", 1.0)]),
            ],
            available: ["img-formality-01-a", "img-formality-01-b"]
        )

        #expect(loaded.pairs.map(\.id) == ["formality-01"])
        #expect(loaded.excluded.map(\.pairID) == ["texture-01"])
        #expect(loaded.excluded.first?.reason.contains("img-texture-01-a") == true)
    }

    @Test("A pair with no accessibility description is refused")
    func missingAlternativeTextIsRefused() throws {
        // The whole question is inside the photograph. Without alternative text
        // the screen is two unlabelled buttons, which spec §19 does not permit —
        // so this is a load-time rejection, not a lint someone can ignore.
        let json = """
        {"version": 1, "pairs": [{"id": "p", \
        "option_a": {"id": "a", "image": "x", "accessibility_description": "  ", \
        "loadings": {"formality": 1}}, \
        "option_b": {"id": "b", "image": "y", "accessibility_description": "Described.", \
        "loadings": {"formality": -1}}}]}
        """
        let loaded = try StyleQuizCatalog.load(
            manifestData: Data(json.utf8),
            locator: AlwaysResolvingImageLocator()
        )
        #expect(loaded.pairs.isEmpty)
        #expect(loaded.excluded.first?.reason.contains("accessibility_description") == true)
    }

    @Test("An unknown dimension is refused rather than silently ignored")
    func unknownDimensionIsRefused() throws {
        let json = """
        {"version": 1, "pairs": [{"id": "p", \
        "option_a": {"id": "a", "image": "x", "accessibility_description": "A.", \
        "loadings": {"vibe": 1}}, \
        "option_b": {"id": "b", "image": "y", "accessibility_description": "B.", \
        "loadings": {"formality": -1}}}]}
        """
        let loaded = try StyleQuizCatalog.load(
            manifestData: Data(json.utf8),
            locator: AlwaysResolvingImageLocator()
        )
        #expect(loaded.pairs.isEmpty)
        #expect(loaded.excluded.first?.reason.contains("vibe") == true)
    }

    @Test("The reserved no-preference id cannot be used as an option id")
    func reservedOptionIDIsRefused() throws {
        let json = """
        {"version": 1, "pairs": [{"id": "p", \
        "option_a": {"id": "no_preference", "image": "x", "accessibility_description": "A.", \
        "loadings": {"formality": 1}}, \
        "option_b": {"id": "b", "image": "y", "accessibility_description": "B.", \
        "loadings": {"formality": -1}}}]}
        """
        let loaded = try StyleQuizCatalog.load(
            manifestData: Data(json.utf8),
            locator: AlwaysResolvingImageLocator()
        )
        #expect(loaded.pairs.isEmpty)
    }

    @Test("Duplicate pair ids are refused; answers are keyed on them")
    func duplicatePairIDsAreRefused() throws {
        let loaded = try catalog([
            ("colour-01", nil, [("colour_tolerance", 1.0)]),
            ("colour-01", nil, [("texture", 1.0)]),
        ])
        #expect(loaded.pairs.count == 1)
        #expect(loaded.excluded.count == 1)
    }

    @Test("Unreadable JSON throws rather than yielding a half-built catalog")
    func unreadableManifestThrows() {
        #expect(throws: StyleQuizCatalogError.self) {
            _ = try StyleQuizCatalog.load(
                manifestData: Data("not json".utf8),
                locator: AlwaysResolvingImageLocator()
            )
        }
    }

    @Test("Axes no comparison touches are reported as unprobed")
    func unprobedAxesAreNamed() throws {
        let loaded = try catalog([("formality-01", nil, [("formality", 1.0)])])
        #expect(loaded.probedDimensions == [.formality])
        #expect(loaded.unprobedDimensions.count == StyleDimension.allCases.count - 1)
        #expect(!loaded.unprobedDimensions.contains(.formality))
    }
}

// MARK: - Sequencing

@Suite("Style quiz — sequencing, resumption and the length the spec asks for")
struct StyleQuizEngineSequencingTests {

    /// Four colour pairs listed before one of each other axis: the manifest
    /// order a content editor naturally produces by adding pairs axis by axis.
    private func lopsidedCatalog() throws -> StyleQuizCatalog {
        try catalog([
            ("colour-01", nil, [("colour_tolerance", 1.0)]),
            ("colour-02", nil, [("colour_tolerance", 1.0)]),
            ("colour-03", nil, [("colour_tolerance", 1.0)]),
            ("colour-04", nil, [("colour_tolerance", 1.0)]),
            ("formality-01", nil, [("formality", 1.0)]),
            ("silhouette-01", nil, [("silhouette", 1.0)]),
        ])
    }

    @Test("Ordering spreads across axes rather than following the manifest")
    func orderingCoversBreadthFirst() throws {
        let engine = StyleQuizEngine(catalog: try lopsidedCatalog())
        let firstThree = engine.comparisons.prefix(3).map(\.id)

        // The point is the man who answers three and leaves — a meaningful share
        // of users on the highest-drop-off surface in the app. In manifest order
        // he hands over three readings of colour and nothing else. Ordered for
        // coverage his three answers touch three different axes.
        #expect(Set(firstThree) == ["colour-01", "formality-01", "silhouette-01"])
        #expect(engine.comparisons.count == 6)
    }

    @Test("Priority decides the opener among equally useful comparisons")
    func priorityChoosesTheOpener() throws {
        let engine = StyleQuizEngine(catalog: try catalog([
            ("colour-01", 50, [("colour_tolerance", 1.0)]),
            ("formality-01", 5, [("formality", 1.0)]),
            ("silhouette-01", 90, [("silhouette", 1.0)]),
        ]))
        #expect(engine.comparisons.first?.id == "formality-01")
    }

    @Test("Ordering is deterministic across rebuilds")
    func orderingIsStable() throws {
        // The sequence is recomputed every time the view rebuilds or a draft is
        // restored. Any dependence on Set or Dictionary iteration order would let
        // the quiz reshuffle itself under a user between two launches.
        let source = try lopsidedCatalog()
        let first = StyleQuizEngine(catalog: source).comparisons.map(\.id)
        for _ in 0..<25 {
            #expect(StyleQuizEngine(catalog: source).comparisons.map(\.id) == first)
        }
    }

    @Test("A run is capped at the twenty comparisons spec §6.9 allows")
    func runIsCappedAtTwenty() throws {
        let many = (1...30).map {
            (id: "pair-\($0)", priority: Optional<Int>.none, loadings: [("formality", 1.0)])
        }
        let engine = StyleQuizEngine(catalog: try catalog(many))
        #expect(engine.catalog.pairs.count == 30)
        #expect(engine.comparisonCount == StyleQuizEngine.maximumComparisons)
        #expect(engine.comparisonCount == 20)
    }

    @Test("Answering walks the sequence and then finishes")
    func answeringWalksTheSequence() throws {
        let engine = StyleQuizEngine(catalog: try lopsidedCatalog())
        var answers: [StylePreferenceQuizAnswer] = []

        for expected in engine.comparisons {
            let next = engine.nextComparison(given: answers)
            #expect(next?.id == expected.id)
            #expect(!engine.isFinished(given: answers))
            answers = try #require(engine.recording(pairID: expected.id, optionID: "a", into: answers))
        }

        #expect(engine.nextComparison(given: answers) == nil)
        #expect(engine.isFinished(given: answers))
        #expect(engine.answeredCount(given: answers) == 6)
    }

    @Test("Re-answering replaces in place rather than appending")
    func reAnsweringReplaces() throws {
        let engine = StyleQuizEngine(catalog: try lopsidedCatalog())
        let first = try #require(engine.comparisons.first)
        var answers = try #require(engine.recording(pairID: first.id, optionID: "a", into: []))
        answers = try #require(engine.recording(pairID: first.id, optionID: "b", into: answers))

        #expect(answers.count == 1)
        #expect(answers.first?.chosenOptionID == "b")
        #expect(engine.answeredCount(given: answers) == 1)
    }

    @Test("An option that is not on the pair is refused")
    func foreignOptionIsRefused() throws {
        let engine = StyleQuizEngine(catalog: try lopsidedCatalog())
        let first = try #require(engine.comparisons.first)
        #expect(engine.recording(pairID: first.id, optionID: "c", into: []) == nil)
        #expect(engine.recording(pairID: "no-such-pair", optionID: "a", into: []) == nil)
        // The reserved pass answer is always accepted.
        #expect(engine.recording(
            pairID: first.id,
            optionID: StyleQuizPair.noPreferenceOptionID,
            into: []
        ) != nil)
    }

    @Test("Undo removes the last answer given, not the last array element")
    func undoRemovesTheLastAnswerGiven() throws {
        let engine = StyleQuizEngine(catalog: try lopsidedCatalog())
        var answers: [StylePreferenceQuizAnswer] = [
            // Left over from a build whose imagery has since been pulled.
            StylePreferenceQuizAnswer(pairID: "retired-pair", chosenOptionID: "a")
        ]
        let first = try #require(engine.comparisons.first)
        answers = try #require(engine.recording(pairID: first.id, optionID: "a", into: answers))
        answers = engine.undoingLastAnswer(in: answers)

        #expect(engine.answeredCount(given: answers) == 0)
        // The stale answer is untouched: undo removes what the user just did,
        // and to him nothing else was ever there.
        #expect(answers.map(\.pairID) == ["retired-pair"])
    }

    @Test("Answers for comparisons this build lacks are ignored, not counted")
    func staleAnswersAreIgnored() throws {
        let engine = StyleQuizEngine(catalog: try lopsidedCatalog())
        let answers = [
            StylePreferenceQuizAnswer(pairID: "retired-pair", chosenOptionID: "a"),
            StylePreferenceQuizAnswer(pairID: "another-retired", chosenOptionID: "b"),
        ]
        // Counting them would put the progress line at "3 of 6" on an untouched
        // step, and at worst past its own denominator.
        #expect(engine.answeredCount(given: answers) == 0)
        #expect(engine.nextComparison(given: answers)?.id == engine.comparisons.first?.id)
    }

    @Test("An empty catalog asks nothing and is immediately finished")
    func emptyCatalogIsFinished() {
        let engine = StyleQuizEngine(catalog: .empty)
        #expect(engine.hasNothingToAsk)
        #expect(engine.comparisonCount == 0)
        #expect(engine.isFinished(given: []))
        #expect(engine.nextComparison(given: []) == nil)
        // Skipping must still produce something a profile can be built from.
        #expect(engine.vector(from: []).isEmpty)
    }

    @Test("The early stop cannot fire below spec §6.9's floor of twelve")
    func earlyStopRespectsTheSpecFloor() throws {
        // Three comparisons, all answered consistently on one axis — the most
        // confident a short run can possibly be. It still may not stop early,
        // because there is nothing to stop short of and, more to the point,
        // because three is under the floor the spec sets.
        let engine = StyleQuizEngine(catalog: try catalog([
            ("f-01", nil, [("formality", 1.0)]),
            ("f-02", nil, [("formality", 1.0)]),
            ("f-03", nil, [("formality", 1.0)]),
        ]))
        var answers: [StylePreferenceQuizAnswer] = []
        answers = try #require(engine.recording(pairID: "f-01", optionID: "a", into: answers))
        answers = try #require(engine.recording(pairID: "f-02", optionID: "a", into: answers))
        #expect(!engine.hasEnoughSignal(given: answers))
        #expect(engine.nextComparison(given: answers)?.id == "f-03")
    }

    @Test("With enough consistent answers the run can stop before the last pair")
    func earlyStopFiresOnceThereIsEnough() throws {
        // Fourteen comparisons on one axis. After twelve consistent answers that
        // axis is `.high`, nothing the remaining two could say would change it,
        // and asking them is asking for nothing.
        let pairs = (1...14).map {
            (id: "f-\($0)", priority: Optional<Int>.none, loadings: [("formality", 1.0)])
        }
        let engine = StyleQuizEngine(catalog: try catalog(pairs))
        var answers: [StylePreferenceQuizAnswer] = []
        for pair in engine.comparisons.prefix(12) {
            answers = try #require(engine.recording(pairID: pair.id, optionID: "a", into: answers))
        }
        #expect(engine.hasEnoughSignal(given: answers))
        #expect(engine.isFinished(given: answers))
    }

    @Test("The shipped catalog is well-formed, and reports its own shortfall")
    func shippedCatalogIsHonestAboutItsLength() {
        // Deliberately does NOT assert a pair count. The comparison set is
        // content: an assertion on today's three would fail the day someone adds
        // the texture pairs, which is precisely the change this design exists to
        // make painless. What is asserted is that whatever ships is internally
        // sound, and that the app's own view of whether it meets §6.9's length is
        // consistent with what it actually holds.
        let catalog = StyleQuizCatalog.bundled(bundle: .main)
        // Asserted first, because every check below it is vacuously true of an
        // empty catalog — and an empty catalog is exactly what a manifest that
        // stopped being copied into the bundle produces. Without this line the
        // whole test would go on passing while the quiz silently had nothing to
        // ask.
        #expect(!catalog.pairs.isEmpty, "No comparison survived loading from the app bundle")
        #expect(catalog.excluded.isEmpty, "A shipped manifest stanza was dropped at load")
        #expect(
            catalog.meetsSpecifiedLength
                == StyleQuizCatalog.specifiedComparisonRange.contains(catalog.pairs.count)
        )

        let engine = StyleQuizEngine(catalog: catalog)
        #expect(engine.comparisonCount <= StyleQuizEngine.maximumComparisons)
        for pair in engine.comparisons {
            #expect(!pair.probedDimensions.isEmpty)
            for option in pair.options {
                #expect(!option.accessibilityDescription.isEmpty)
                #expect(option.id != StyleQuizPair.noPreferenceOptionID)
            }
        }
    }
}
