//
//  FreeTierCappedClosetRepository.swift
//  AstraStyle
//
//  Spec §16 free-tier 30-item closet cap, enforced at the
//  `ClosetRepository` boundary rather than at each call site.
//  `AppContainer` wraps the live (or mock) closet repository with this
//  type and injects the result everywhere, so every create path shares
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
    private let isAnonymous: @Sendable () async -> Bool

    public init(
        base: ClosetRepository,
        isEntitledToPremium: @escaping @Sendable () async -> Bool,
        isAnonymous: @escaping @Sendable () async -> Bool = { false }
    ) {
        self.base = base
        self.isEntitledToPremium = isEntitledToPremium
        self.isAnonymous = isAnonymous
    }

    private func capLimit() async -> Int {
        await isAnonymous() ? GuestLimits.maxClosetItems : FreeTierLimits.maxClosetItems
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

    /// Checks the cap BEFORE the batch is analysed, not at save.
    ///
    /// This used to be a bare pass-through, which meant a free-tier user two
    /// items from the cap could hand over twenty photographs, wait through
    /// twenty vision calls, and then be refused at the eighteenth `createItem`
    /// — having paid, in real provider spend, for eighteen readings he could
    /// never keep. The cap is the same cap; it was simply enforced at the
    /// wrong end of the flow.
    ///
    /// The whole batch is refused rather than trimmed to whatever fits.
    /// Analysing five of twenty and saying nothing is the silent loss
    /// `ScannerBatchViewModel.Outcome` exists to make impossible, and
    /// trimming would need to pick WHICH five — a choice the user is better
    /// placed to make by choosing fewer photographs.
    public func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        if await isEntitledToPremium() == false {
            let activeCount = try await base.fetchItems().count
            let headroom = await capLimit() - activeCount
            guard headroom >= requests.count else {
                throw FreeTierClosetError.capReached(limit: await capLimit())
            }
        }
        return try await base.batchAnalyzeItems(requests)
    }

    public func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        if await isEntitledToPremium() == false {
            let activeCount = try await base.fetchItems().count
            let limit = await capLimit()
            guard activeCount < limit else {
                throw FreeTierClosetError.capReached(limit: limit)
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
