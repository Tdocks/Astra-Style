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

    public init(items: [ClosetItem] = SampleData.closetItems) {
        self.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
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

    public func analyzeItem(imageData: Data, imageType: ClosetImageType) async throws -> ClosetItemAnalysisResult {
        ClosetItemAnalysisResult(
            suggestedName: FieldSuggestion(value: "Cotton Crewneck Sweater", confidence: 0.88),
            suggestedBrand: FieldSuggestion(value: "Uniqlo", confidence: 0.52),
            suggestedCategory: FieldSuggestion(value: .top, confidence: 0.95),
            suggestedSubcategory: FieldSuggestion(value: "Sweater", confidence: 0.81),
            suggestedPrimaryColor: FieldSuggestion(value: "navy", confidence: 0.9),
            suggestedPattern: FieldSuggestion(value: .solid, confidence: 0.93),
            suggestedMaterial: ["cotton"],
            suggestedCondition: FieldSuggestion(value: .good, confidence: 0.7)
        )
    }

    public func batchAnalyzeItems(imageDataList: [Data]) async throws -> [ClosetItemAnalysisResult] {
        try await withThrowingTaskGroup(of: ClosetItemAnalysisResult.self) { group in
            for data in imageDataList {
                group.addTask { try await self.analyzeItem(imageData: data, imageType: .front) }
            }
            var results: [ClosetItemAnalysisResult] = []
            for try await result in group { results.append(result) }
            return results
        }
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
