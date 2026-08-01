//
//  ClosetItemAnalysisResultTests.swift
//  AstraStyleTests
//
//  Spec §12 (the scan pipeline's server-side leg and its "all inferred
//  fields remain editable, low-confidence fields visibly marked" user
//  verification rule) and §6.16 (the review screen and batch closet scan).
//
//  `ModelCodableRoundTripTests` covers the persisted models — the ones with
//  a Postgres table behind them. `ClosetItemAnalysisResult` has none: it is
//  a pure wire contract between an Edge Function and one screen, and its
//  failure modes are different in kind. A persisted model that mis-maps a
//  key fails loudly at INSERT; this one silently drops a suggestion, or
//  attaches one garment's analysis to another garment's photo. So it gets
//  its own suite rather than three more cases appended to that file.
//
//  Each test below states what it asserts and why that assertion is the one
//  that matters, because several of these look like tautologies until you
//  know which specific bug they exist to prevent.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("ClosetItemAnalysisResult — spec §12 scan analysis contract")
struct ClosetItemAnalysisResultTests {

    // MARK: - Fixtures

    private var decoder: JSONDecoder { JSONDecoder() }
    private var encoder: JSONEncoder { JSONEncoder() }

    /// The full payload, written by hand in the exact snake_case shape the
    /// Edge Function is specified to return. Hand-written rather than
    /// produced by encoding a Swift value on purpose: a fixture generated
    /// from the type under test agrees with that type by construction, so it
    /// cannot catch the one thing this suite most needs to catch — the Swift
    /// side and the server side disagreeing about a key's name.
    private func fullPayloadJSON() -> Data {
        Data("""
        {
          "name": {"value": "Cotton Crewneck Sweater", "confidence": 0.88},
          "brand": {"value": "Uniqlo", "confidence": 0.52},
          "category": {"value": "top", "confidence": 0.95},
          "subcategory": {"value": "Sweater", "confidence": 0.81},
          "primary_color": {"value": "navy", "confidence": 0.9},
          "secondary_colors": [{"value": "cream", "confidence": 0.66}],
          "pattern": {"value": "solid", "confidence": 0.93},
          "material": [
            {"value": "wool", "confidence": 0.91},
            {"value": "nylon", "confidence": 0.41}
          ],
          "size": {"value": "M", "confidence": 0.74},
          "fit": {"value": "regular", "confidence": 0.68},
          "condition": {"value": "good", "confidence": 0.7},
          "seasonality": [
            {"value": "fall", "confidence": 0.83},
            {"value": "all_season", "confidence": 0.62}
          ],
          "formality_score": {"value": 35, "confidence": 0.77},
          "warmth_score": {"value": 62, "confidence": 0.72},
          "water_resistance_score": {"value": 10, "confidence": 0.64},
          "normalized_image_path": "users/abc/closet/cutout.png",
          "ocr_text": "100% COTTON\\nSIZE M",
          "fields_below_confidence_threshold": ["brand", "size"]
        }
        """.utf8)
    }

    private func makeResult(
        category: FieldSuggestion<ClothingCategory> = FieldSuggestion(value: .top, confidence: 0.95),
        brand: FieldSuggestion<String>? = nil,
        material: [FieldSuggestion<String>] = [],
        serverFlags: Set<AnalysisField> = []
    ) -> ClosetItemAnalysisResult {
        ClosetItemAnalysisResult(
            brand: brand,
            category: category,
            material: material,
            fieldsBelowConfidenceThreshold: serverFlags
        )
    }

    // MARK: - Wire format

    @Test("Every field decodes from the exact snake_case keys the Edge Function sends, because a key this side spells differently is a suggestion the user silently never sees")
    func decodesTheEdgeFunctionPayload() throws {
        let result = try decoder.decode(ClosetItemAnalysisResult.self, from: fullPayloadJSON())

        #expect(result.name?.value == "Cotton Crewneck Sweater")
        #expect(result.brand?.confidence == 0.52)
        #expect(result.category.value == .top)
        #expect(result.subcategory?.value == "Sweater")
        #expect(result.primaryColor?.value == "navy")
        #expect(result.secondaryColors.map(\.value) == ["cream"])
        #expect(result.pattern?.value == .solid)
        #expect(result.material.map(\.value) == ["wool", "nylon"])
        #expect(result.size?.value == "M")
        #expect(result.fit?.value == .regular)
        #expect(result.condition?.value == .good)
        #expect(result.seasonality.map(\.value) == [.fall, .allSeason])
        #expect(result.formalityScore?.value == 35)
        #expect(result.warmthScore?.value == 62)
        #expect(result.waterResistanceScore?.value == 10)
        #expect(result.normalizedImagePath == "users/abc/closet/cutout.png")
        #expect(result.ocrText == "100% COTTON\nSIZE M")
        #expect(result.fieldsBelowConfidenceThreshold == [.brand, .size])
    }

    @Test("A decoded result re-encodes to a value that decodes back identically, so the client can round-trip an analysis through local storage or a retry without losing a field")
    func roundTripsThroughEncodeAndDecode() throws {
        let original = try decoder.decode(ClosetItemAnalysisResult.self, from: fullPayloadJSON())

        let reEncoded = try encoder.encode(original)
        let decoded = try decoder.decode(ClosetItemAnalysisResult.self, from: reEncoded)

        #expect(decoded == original)
    }

    @Test("Encoding emits snake_case keys, not Swift property names — a Swift-to-Swift round trip passes even when both ends use the wrong key, so the emitted keys are checked as strings")
    func encodesSnakeCaseKeys() throws {
        let original = try decoder.decode(ClosetItemAnalysisResult.self, from: fullPayloadJSON())
        let data = try encoder.encode(original)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let expected: Set<String> = [
            "name", "brand", "category", "subcategory", "primary_color",
            "secondary_colors", "pattern", "material", "size", "fit",
            "condition", "seasonality", "formality_score", "warmth_score",
            "water_resistance_score", "normalized_image_path", "ocr_text",
            "fields_below_confidence_threshold"
        ]
        #expect(Set(object.keys) == expected)
    }

    @Test("A payload carrying only `category` decodes, because §2.2 of the provider doc has the degraded path omit every other key and a scan that returns almost nothing must still be correctable rather than a decode failure")
    func decodesPayloadWithEveryOptionalAbsent() throws {
        let json = Data("""
        {"category": {"value": "outerwear", "confidence": 0.44}}
        """.utf8)

        let result = try decoder.decode(ClosetItemAnalysisResult.self, from: json)

        #expect(result.category.value == .outerwear)
        #expect(result.name == nil)
        #expect(result.fit == nil)
        // The list fields default to empty rather than staying nil: an absent
        // `material` means "nothing inferred", and modelling that as an
        // optional array would push a `?? []` onto every call site.
        #expect(result.secondaryColors.isEmpty)
        #expect(result.material.isEmpty)
        #expect(result.seasonality.isEmpty)
        #expect(result.fieldsBelowConfidenceThreshold.isEmpty)
    }

    @Test("An unrecognised field name in the server's flag list is dropped rather than failing the decode, so a server that starts flagging a field this build predates does not break scanning outright")
    func unknownFlaggedFieldNameIsDropped() throws {
        let json = Data("""
        {
          "category": {"value": "top", "confidence": 0.9},
          "fields_below_confidence_threshold": ["brand", "sleeve_length"]
        }
        """.utf8)

        let result = try decoder.decode(ClosetItemAnalysisResult.self, from: json)

        #expect(result.fieldsBelowConfidenceThreshold == [.brand])
    }

    // MARK: - The low-confidence predicate

    @Test("Confidence exactly at the threshold is NOT low-confidence — the comparison is strictly less-than, and a boundary that flips would mark or un-mark every field the model reports at exactly the cut point")
    func confidenceAtThresholdIsNotLow() {
        let suggestion = FieldSuggestion(value: "Uniqlo", confidence: AnalysisConfidence.lowConfidenceThreshold)

        #expect(suggestion.isLowConfidence == false)
    }

    @Test("Confidence just below the threshold is low-confidence, which is the case the review screen's marking exists for")
    func confidenceJustBelowThresholdIsLow() {
        let suggestion = FieldSuggestion(value: "Uniqlo", confidence: AnalysisConfidence.lowConfidenceThreshold - 0.001)

        #expect(suggestion.isLowConfidence)
    }

    @Test("Confidence just above the threshold is not low-confidence, so a confident field is never decorated as a guess")
    func confidenceJustAboveThresholdIsNotLow() {
        let suggestion = FieldSuggestion(value: "Uniqlo", confidence: AnalysisConfidence.lowConfidenceThreshold + 0.001)

        #expect(suggestion.isLowConfidence == false)
    }

    @Test("An injected threshold is honoured, so a remotely-configured cut point does not have to route through the compiled-in default")
    func injectedThresholdIsHonoured() {
        let suggestion = FieldSuggestion(value: "Uniqlo", confidence: 0.7)

        #expect(suggestion.isLowConfidence == false)
        #expect(suggestion.isLowConfidence(below: 0.8))
    }

    // MARK: - Stored flags unioned with computed flags

    @Test("A field the server flags is marked even though its confidence is above the client threshold, because §2.2's degraded path flags fields for reasons the client cannot reconstruct")
    func serverFlagMarksAnOtherwiseConfidentField() {
        let result = makeResult(
            brand: FieldSuggestion(value: "Uniqlo", confidence: 0.95),
            serverFlags: [.brand]
        )

        #expect(result.isLowConfidence(.brand))
        #expect(result.lowConfidenceFields.contains(.brand))
    }

    @Test("A field below the client threshold is marked even when the server's flag list omits it, so an Edge Function that forgets to populate the list cannot produce an unmarked guess")
    func computedThresholdMarksAFieldTheServerOmitted() {
        let result = makeResult(
            brand: FieldSuggestion(value: "Uniqlo", confidence: 0.3),
            serverFlags: []
        )

        #expect(result.isLowConfidence(.brand))
    }

    @Test("A high-confidence field the server did not flag is not marked, confirming the union adds marks rather than marking everything")
    func confidentUnflaggedFieldIsNotMarked() {
        let result = makeResult(brand: FieldSuggestion(value: "Uniqlo", confidence: 0.95))

        #expect(result.isLowConfidence(.brand) == false)
        #expect(result.lowConfidenceFields.isEmpty)
    }

    @Test("A list field is marked when any single element is low-confidence, because '80% wool, 20% nylon' can be certain about the wool and guessing at the nylon and the user needs to be told which chip to check")
    func listFieldIsMarkedWhenAnyElementIsLowConfidence() {
        let result = makeResult(material: [
            FieldSuggestion(value: "wool", confidence: 0.94),
            FieldSuggestion(value: "nylon", confidence: 0.35)
        ])

        #expect(result.isLowConfidence(.material))
        // Per-element confidence survives, so the review screen can mark the
        // nylon chip specifically instead of the whole row.
        #expect(result.material.map(\.isLowConfidence) == [false, true])
    }

    @Test("Only the four fields the routing doc names qualify for a server-side re-analysis, so the client and the Edge Function cannot hold different opinions about which low-confidence fields are worth escalating")
    func onlyTheDocumentedFieldsQualifyForEscalation() {
        let qualifying = AnalysisField.allCases.filter(\.qualifiesForConfidenceEscalation)

        #expect(Set(qualifying) == [.category, .subcategory, .material, .condition])
    }
}

/// Spec §6.16 "Batch closet scan". The two acceptance criteria this suite
/// exists for are that one item failing does not fail the batch, and that
/// five submitted images come back as five independently correctable
/// results. Both are properties of the *shape*, not of any implementation:
/// the previous `[Data] -> [ClosetItemAnalysisResult]` signature could not
/// express either one, which is why the shape changed before the flow was
/// built on top of it.
@Suite("ClosetItemAnalysisBatch — spec §6.16 batch closet scan")
struct ClosetItemAnalysisBatchTests {

    private var decoder: JSONDecoder { JSONDecoder() }
    private var encoder: JSONEncoder { JSONEncoder() }

    /// Distinguishable per-item results, so a test that asserts "this
    /// request got its own analysis" can actually tell two analyses apart —
    /// identical fixtures would make a mis-attribution invisible.
    private func makeResult(subcategory: String) -> ClosetItemAnalysisResult {
        ClosetItemAnalysisResult(
            category: FieldSuggestion(value: .top, confidence: 0.9),
            subcategory: FieldSuggestion(value: subcategory, confidence: 0.8)
        )
    }

    private func makeRequests(_ count: Int) -> [ClosetItemAnalysisRequest] {
        (0..<count).map { index in
            ClosetItemAnalysisRequest(imageData: Data("photo-\(index)".utf8))
        }
    }

    @Test("A batch in which one item failed still carries the other items' results, because a single unusable photo must cost the user that photo and not the other four")
    func oneFailedItemDoesNotLoseTheOthers() throws {
        let requests = makeRequests(3)
        let batch = ClosetItemAnalysisBatch(results: [
            ClosetItemAnalysisBatchItem(id: requests[0].id, outcome: .analyzed(makeResult(subcategory: "Sweater"))),
            ClosetItemAnalysisBatchItem(id: requests[1].id, outcome: .failed(ClosetItemAnalysisFailure(reason: .imageUnusable))),
            ClosetItemAnalysisBatchItem(id: requests[2].id, outcome: .analyzed(makeResult(subcategory: "Oxford shirt")))
        ])

        #expect(batch.analyzed.count == 2)
        #expect(batch.result(for: requests[0].id)?.subcategory?.value == "Sweater")
        #expect(batch.result(for: requests[2].id)?.subcategory?.value == "Oxford shirt")
        #expect(batch.isPartialFailure)
    }

    @Test("The batch names which item failed and why, so the flow can offer a retake on that one capture instead of asking the user to rescan everything")
    func batchIdentifiesTheFailedItem() throws {
        let requests = makeRequests(3)
        let batch = ClosetItemAnalysisBatch(results: [
            ClosetItemAnalysisBatchItem(id: requests[0].id, outcome: .analyzed(makeResult(subcategory: "Sweater"))),
            ClosetItemAnalysisBatchItem(id: requests[1].id, outcome: .failed(ClosetItemAnalysisFailure(reason: .imageUnusable))),
            ClosetItemAnalysisBatchItem(id: requests[2].id, outcome: .analyzed(makeResult(subcategory: "Oxford shirt")))
        ])

        #expect(Set(batch.failures.keys) == [requests[1].id])
        let failure = try #require(batch.failure(for: requests[1].id))
        #expect(failure.reason == .imageUnusable)
        #expect(batch.result(for: requests[1].id) == nil)
    }

    @Test("Results are matched by request id, not array position: a response deliberately returned in reverse order still lands each analysis on the request that produced it")
    func resultsAreMatchedByIdentityNotPosition() throws {
        let requests = makeRequests(3)
        let labels = ["first", "second", "third"]

        // Deliberately reversed. The server is free to do this — a provider
        // batch endpoint (docs/08 §2.3) has no obligation to preserve
        // submission order, and the mock's task-group fan-out did not.
        let batch = ClosetItemAnalysisBatch(results: zip(requests, labels).reversed().map { request, label in
            ClosetItemAnalysisBatchItem(id: request.id, outcome: .analyzed(makeResult(subcategory: label)))
        })

        #expect(batch.results.first?.id == requests[2].id)
        for (request, label) in zip(requests, labels) {
            #expect(batch.result(for: request.id)?.subcategory?.value == label)
        }
    }

    @Test("A batch decodes from the response body the Edge Function sends, with `request_id` echoing the client's id and per-item `result`/`error` slots")
    func decodesTheEdgeFunctionBatchBody() throws {
        let first = UUID()
        let second = UUID()
        let json = Data("""
        {
          "results": [
            {
              "request_id": "\(first.uuidString)",
              "result": {"category": {"value": "top", "confidence": 0.9}}
            },
            {
              "request_id": "\(second.uuidString)",
              "error": {"reason": "provider_unavailable", "message": "vision provider exhausted retries"}
            }
          ]
        }
        """.utf8)

        let batch = try decoder.decode(ClosetItemAnalysisBatch.self, from: json)

        #expect(batch.result(for: first)?.category.value == .top)
        let failure = try #require(batch.failure(for: second))
        #expect(failure.reason == .providerUnavailable)
        #expect(failure.message == "vision provider exhausted retries")
    }

    @Test("A batch round-trips through encode and decode unchanged, so a partially-failed batch can be cached or replayed without the failures quietly becoming successes")
    func batchRoundTrips() throws {
        let requests = makeRequests(2)
        let original = ClosetItemAnalysisBatch(results: [
            ClosetItemAnalysisBatchItem(id: requests[0].id, outcome: .analyzed(makeResult(subcategory: "Sweater"))),
            ClosetItemAnalysisBatchItem(id: requests[1].id, outcome: .failed(ClosetItemAnalysisFailure(reason: .timedOut, message: "latency ceiling exceeded")))
        ])

        let decoded = try decoder.decode(ClosetItemAnalysisBatch.self, from: try encoder.encode(original))

        #expect(decoded == original)
    }

    @Test("A failure reason this build does not recognise decodes to `unknown` rather than throwing, because one new server-side reason must not make an entire batch undecodable on already-shipped clients")
    func unknownFailureReasonDecodesToUnknown() throws {
        let json = Data("""
        {"reason": "an_unrecognised_new_reason", "message": "added server-side after this build shipped"}
        """.utf8)

        let failure = try decoder.decode(ClosetItemAnalysisFailure.self, from: json)

        #expect(failure.reason == .unknown)
        #expect(failure.reason.isRetryable == false)
    }

    @Test("An item carrying both a result and an error is read as failed — the conservative reading, which shows a retry affordance rather than accepting suggestions the server itself flagged as broken")
    func itemWithBothResultAndErrorIsReadAsFailed() throws {
        let requestID = UUID()
        let json = Data("""
        {
          "request_id": "\(requestID.uuidString)",
          "result": {"category": {"value": "top", "confidence": 0.9}},
          "error": {"reason": "no_garment_detected"}
        }
        """.utf8)

        let item = try decoder.decode(ClosetItemAnalysisBatchItem.self, from: json)

        #expect(item.id == requestID)
        #expect(item.outcome.failure?.reason == .noGarmentDetected)
        #expect(item.outcome.result == nil)
    }

    @Test("Only failures a resubmission could plausibly clear are retryable, so the review screen never offers a retry control that cannot succeed (spec §22: no dead buttons)")
    func onlyTransientFailuresAreRetryable() {
        let retryable = ClosetItemAnalysisFailureReason.allCases.filter(\.isRetryable)

        #expect(Set(retryable) == [.providerUnavailable, .rateLimited, .timedOut])
    }

    @Test("The mock repository attributes each analysis to the request that produced it, which its previous fan-out could not do — it appended results in completion order and returned a bare array")
    func mockBatchAttributesResultsToRequests() async throws {
        let repository = MockClosetRepository(items: [], previewBatchFailureIndex: nil)
        let requests = makeRequests(5)

        let batch = try await repository.batchAnalyzeItems(requests)

        #expect(batch.results.count == 5)
        #expect(Set(batch.results.map(\.id)) == Set(requests.map(\.id)))
        #expect(batch.failures.isEmpty)
    }

    @Test("The mock's default batch returns four successes and one failure, so the partial-failure path is previewable under the mock backend for the same reason its brand confidence is deliberately low")
    func mockBatchPreviewsAPartialFailure() async throws {
        let repository = MockClosetRepository(items: [])
        let requests = makeRequests(5)

        let batch = try await repository.batchAnalyzeItems(requests)

        #expect(batch.analyzed.count == 4)
        #expect(Set(batch.failures.keys) == [requests[3].id])
        #expect(batch.isPartialFailure)
    }
}
