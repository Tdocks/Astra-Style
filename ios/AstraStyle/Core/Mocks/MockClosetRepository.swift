//
//  MockClosetRepository.swift
//  AstraStyle
//
//  In-memory `ClosetRepository` for previews/tests, seeded with the
//  25-item sample wardrobe (spec §31).
//

import Foundation

public actor MockClosetRepository: ClosetRepository {
    private var items: [UUID: ClosetItem]
    private let previewBatchFailureIndex: Int?

    /// - Parameter previewBatchFailureIndex: which submission index of a
    ///   batch scan comes back failed. This exists for the same reason the
    ///   canned analysis below sets brand confidence to 0.52: the review
    ///   screen's degraded paths have to be reachable under
    ///   `-astra-mock-backend` without a server, or they get built against
    ///   nothing and only get looked at once real analysis is wired up. The
    ///   default (index 3) leaves single captures and small batches entirely
    ///   successful while making the five-image batch the scan flow is
    ///   designed around show four successes and one failure. Pass `nil` for
    ///   an all-successful batch.
    public init(items: [ClosetItem] = SampleData.closetItems, previewBatchFailureIndex: Int? = 3) {
        self.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        self.previewBatchFailureIndex = previewBatchFailureIndex
    }

    public func fetchItems() async throws -> [ClosetItem] {
        items.values.filter { !$0.isArchived }.sorted { $0.createdAt > $1.createdAt }
    }

    public func fetchItem(id: UUID) async throws -> ClosetItem {
        guard let item = items[id] else {
            throw AstraError.server("That item couldn't be found.")
        }
        return item
    }

    public func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] {
        [
            ClosetItemImage(id: UUID(), closetItemID: itemID, imageType: .front, storagePath: "preview/\(itemID.uuidString)-front.jpg", isPrimary: true)
        ]
    }

    /// The canned analysis the mock backend serves.
    ///
    /// The confidences are chosen, not arbitrary. Brand sits at 0.52 and the
    /// nylon in the material list at 0.41 — both below
    /// `AnalysisConfidence.lowConfidenceThreshold` — so that the review
    /// screen's low-confidence marking is visible under
    /// `-astra-mock-backend` with no server: one whole-field marker (brand)
    /// and one single-chip marker inside an otherwise confident list, which
    /// are two different pieces of UI. `fieldsBelowConfidenceThreshold`
    /// additionally names `size` at a confidence the client would consider
    /// fine (0.74), exercising the server-declares-it-anyway half of the
    /// marking rule that a purely computed predicate would miss.
    public func uploadCapturedImage(_ data: Data) async throws -> String {
        _ = data
        return "users/preview/closet/\(UUID().uuidString.lowercased()).jpg"
    }

    public func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        Self.cannedAnalysis
    }

    /// `nonisolated static` so the batch fan-out's child tasks can build it
    /// without hopping back onto this actor — the fixture depends on nothing
    /// mutable, so serialising N copies of it through the actor would be a
    /// bottleneck invented purely to satisfy isolation.
    nonisolated static var cannedAnalysis: ClosetItemAnalysisResult {
        ClosetItemAnalysisResult(
            name: FieldSuggestion(value: "Cotton Crewneck Sweater", confidence: 0.88),
            brand: FieldSuggestion(value: "Uniqlo", confidence: 0.52),
            category: FieldSuggestion(value: .top, confidence: 0.95),
            subcategory: FieldSuggestion(value: "Sweater", confidence: 0.81),
            primaryColor: FieldSuggestion(value: "navy", confidence: 0.9),
            secondaryColors: [FieldSuggestion(value: "cream", confidence: 0.66)],
            pattern: FieldSuggestion(value: .solid, confidence: 0.93),
            material: [
                FieldSuggestion(value: "cotton", confidence: 0.91),
                FieldSuggestion(value: "nylon", confidence: 0.41)
            ],
            size: FieldSuggestion(value: "M", confidence: 0.74),
            fit: FieldSuggestion(value: .regular, confidence: 0.68),
            condition: FieldSuggestion(value: .good, confidence: 0.7),
            seasonality: [
                FieldSuggestion(value: .fall, confidence: 0.83),
                FieldSuggestion(value: .winter, confidence: 0.79)
            ],
            formalityScore: FieldSuggestion(value: 35, confidence: 0.77),
            warmthScore: FieldSuggestion(value: 62, confidence: 0.72),
            waterResistanceScore: FieldSuggestion(value: 10, confidence: 0.64),
            ocrText: "100% COTTON\nMADE IN VIETNAM\nSIZE M",
            fieldsBelowConfidenceThreshold: [.size]
        )
    }

    public func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        // The previous implementation appended `withThrowingTaskGroup`
        // results in completion order and returned a bare array, so the
        // caller's Nth photo could receive the Mth photo's analysis — a
        // silent mis-attribution, not a crash. The group now carries each
        // request's id with its outcome, and the batch is reassembled in
        // submission order so preview output is stable run to run. Nothing
        // downstream should depend on that order (`ClosetItemAnalysisBatch`
        // is looked up by id), but a mock that shuffles its own output every
        // run makes every screenshot and snapshot diff noise.
        let failureIndex = previewBatchFailureIndex
        let outcomes = await withTaskGroup(of: (UUID, ClosetItemAnalysisOutcome).self) { group in
            for (index, request) in requests.enumerated() {
                let requestID = request.id
                group.addTask {
                    if index == failureIndex {
                        let failure = ClosetItemAnalysisFailure(reason: .imageUnusable, message: "Preview fixture: this capture is deliberately unusable.")
                        return (requestID, .failed(failure))
                    }
                    return (requestID, .analyzed(Self.cannedAnalysis))
                }
            }
            var collected: [UUID: ClosetItemAnalysisOutcome] = [:]
            for await (id, outcome) in group { collected[id] = outcome }
            return collected
        }

        return ClosetItemAnalysisBatch(
            results: requests.compactMap { request in
                outcomes[request.id].map { ClosetItemAnalysisBatchItem(id: request.id, outcome: $0) }
            }
        )
    }

    public func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        items[item.id] = item
        return item
    }

    public func updateItem(_ item: ClosetItem) async throws -> ClosetItem {
        items[item.id] = item
        return item
    }

    public func archiveItem(id: UUID) async throws {
        items[id]?.archivedAt = .now
    }

    public func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem {
        guard var item = items[id] else {
            throw AstraError.server("That item couldn't be found.")
        }
        item.wearCount += 1
        item.lastWornAt = wornAt
        item.laundryState = .wornOnce
        items[id] = item
        return item
    }

    public func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        guard var item = items[id] else {
            throw AstraError.server("That item couldn't be found.")
        }
        item.laundryState = state
        items[id] = item
        return item
    }

    public func fetchWardrobeScore() async throws -> WardrobeScore {
        SampleData.wardrobeScore
    }
}
