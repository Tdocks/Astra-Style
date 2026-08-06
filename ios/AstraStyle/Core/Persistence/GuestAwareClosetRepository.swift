//
//  GuestAwareClosetRepository.swift
//  AstraStyle
//
//  The single `ClosetRepository` `AppContainer` hands to every feature —
//  routes each call to the fully local, network-free `GuestClosetRepository`
//  while the current session is a guest, and to the real (Supabase-backed)
//  repository otherwise. This is what makes "guest mode never reaches
//  Supabase, from any screen" a property of the dependency graph rather
//  than something each Closet screen has to remember to check: since every
//  feature receives this same wrapper (not `LiveClosetRepository`
//  directly), there is no call site that can accidentally bypass the guest
//  gate.
//

import Foundation

public struct GuestAwareClosetRepository: ClosetRepository {
    private let isGuest: @Sendable () async -> Bool
    private let guestRepository: ClosetRepository
    private let liveRepository: ClosetRepository

    public init(
        isGuest: @escaping @Sendable () async -> Bool,
        guestRepository: ClosetRepository,
        liveRepository: ClosetRepository
    ) {
        self.isGuest = isGuest
        self.guestRepository = guestRepository
        self.liveRepository = liveRepository
    }

    private func active() async -> ClosetRepository {
        await isGuest() ? guestRepository : liveRepository
    }

    public func fetchItems() async throws -> [ClosetItem] {
        try await active().fetchItems()
    }

    public func fetchItem(id: UUID) async throws -> ClosetItem {
        try await active().fetchItem(id: id)
    }

    public func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage] {
        try await active().fetchImages(forItem: itemID)
    }

    public func uploadCapturedImage(_ data: Data) async throws -> String {
        try await active().uploadCapturedImage(data)
    }

    public func deleteCapturedImage(atPath storagePath: String) async throws {
        try await active().deleteCapturedImage(atPath: storagePath)
    }

    public func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        try await active().analyzeItem(request)
    }

    public func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        try await active().batchAnalyzeItems(requests)
    }

    public func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem {
        try await active().createItem(item, images: images)
    }

    public func updateItem(_ item: ClosetItem) async throws -> ClosetItem {
        try await active().updateItem(item)
    }

    public func archiveItem(id: UUID) async throws {
        try await active().archiveItem(id: id)
    }

    public func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem {
        try await active().markWorn(id: id, wornAt: wornAt)
    }

    public func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem {
        try await active().updateLaundryState(id: id, state: state)
    }

    public func fetchWardrobeScore() async throws -> WardrobeScore {
        try await active().fetchWardrobeScore()
    }
}
