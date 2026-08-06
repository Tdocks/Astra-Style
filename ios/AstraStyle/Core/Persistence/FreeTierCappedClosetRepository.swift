//
//  FreeTierCappedClosetRepository.swift
//  AstraStyle
//
//  Spec §16 free-tier 30-item closet cap, enforced at the
//  `ClosetRepository` boundary the same way `GuestClosetRepository`
//  enforces the guest 10-item cap. `AppContainer` wraps the live (or
//  mock) closet repository with this type before handing it to
//  `GuestAwareClosetRepository`, so every signed-in create path shares
//  one check.
//
//  Premium uncapping consults `isEntitledToPremium` — typically
//  `Subscription.isEntitledToPremium` via `SubscriptionRepository`.
//  When that closure returns true the cap is not applied. Paywall UI
//  for the failure case is Phase 7 (`P7-SUB-05`); this type only throws
//  `FreeTierClosetError.capReached` so the form can show a clear limit
//  notice without inventing a purchase surface here.
//

import Foundation

public struct FreeTierCappedClosetRepository: ClosetRepository {
    private let base: ClosetRepository
    private let isEntitledToPremium: @Sendable () async -> Bool

    public init(
        base: ClosetRepository,
        isEntitledToPremium: @escaping @Sendable () async -> Bool
    ) {
        self.base = base
        self.isEntitledToPremium = isEntitledToPremium
    }

    public func fetchItems() async throws -> [ClosetItem] {
        try await base.fetchItems()
    }

    public func fetchItem(id: UUID) async throws -> ClosetItem {
        try await base.fetchItem(id: id)
    }

    public func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] {
        try await base.fetchImages(forItem: itemID)
    }

    public func uploadCapturedImage(_ data: Data) async throws -> String {
        try await base.uploadCapturedImage(data)
    }

    public func deleteCapturedImage(atPath storagePath: String) async throws {
        try await base.deleteCapturedImage(atPath: storagePath)
    }

    public func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        try await base.analyzeItem(request)
    }

    public func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        try await base.batchAnalyzeItems(requests)
    }

    public func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        if await isEntitledToPremium() == false {
            let activeCount = try await base.fetchItems().count
            guard activeCount < FreeTierLimits.maxClosetItems else {
                throw FreeTierClosetError.capReached(limit: FreeTierLimits.maxClosetItems)
            }
        }
        return try await base.createItem(item, images: images)
    }

    public func updateItem(_ item: ClosetItem) async throws -> ClosetItem {
        try await base.updateItem(item)
    }

    public func archiveItem(id: UUID) async throws {
        try await base.archiveItem(id: id)
    }

    public func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem {
        try await base.markWorn(id: id, wornAt: wornAt)
    }

    public func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        try await base.updateLaundryState(id: id, state: state)
    }

    public func fetchWardrobeScore() async throws -> WardrobeScore {
        try await base.fetchWardrobeScore()
    }
}
