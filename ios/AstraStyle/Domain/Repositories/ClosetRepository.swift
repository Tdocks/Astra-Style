//
//  ClosetRepository.swift
//  AstraStyle
//
//  Owns `closet_items` / `closet_item_images` (spec §9) and the scan
//  analysis pipeline (spec §12, §14 `closet/analyze-item` and
//  `closet/batch-analyze`).
//
//  Mutations queue for offline sync per spec §7 "Offline behavior" — Live
//  conformances are expected to write through `OfflineMutationQueue` when
//  the device has no connectivity, rather than failing outright.
//

import Foundation

public protocol ClosetRepository: Sendable {
    func fetchItems() async throws -> [ClosetItem]
    func fetchItem(id: UUID) async throws -> ClosetItem
    func fetchImages(forItem itemID: UUID) async throws -> [ClosetItemImage]

    /// Uploads a captured image and returns the server's analysis
    /// suggestion for review (spec §6.16 "Review screen"). Does not create
    /// a `ClosetItem` by itself — call `createItem` once the user confirms.
    ///
    /// Takes the same request type as the batch call so that a single scan
    /// and one element of a batch scan are literally the same input — the
    /// Edge Function's two endpoints then share one element schema, and a
    /// device hint added for one is available to the other for free.
    func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult

    /// Batch variant for the closet scan flow (spec §6.16 "Batch closet
    /// scan").
    ///
    /// Returns a batch keyed by `ClosetItemAnalysisRequest.id`, not an array
    /// of successes. Throwing on the first bad item would fail the whole
    /// batch, and returning `[ClosetItemAnalysisResult]` cannot express
    /// "item 3 failed" at all — one image failing must cost the user that
    /// one image, not the other four.
    func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch

    func createItem(_ item: ClosetItem, images: [ClosetItemImage]) async throws -> ClosetItem
    func updateItem(_ item: ClosetItem) async throws -> ClosetItem
    func archiveItem(id: UUID) async throws

    func markWorn(id: UUID, wornAt: Date) async throws -> ClosetItem
    func updateLaundryState(id: UUID, state: LaundryState) async throws -> ClosetItem

    /// Wardrobe Score composite (spec §10) for the current user's closet.
    func fetchWardrobeScore() async throws -> WardrobeScore
}

/// The 0–100 composite Wardrobe Score plus its component breakdown
/// (spec §10 "Wardrobe score").
public struct WardrobeScore: Codable, Hashable, Sendable {
    public var overall: Int
    public var versatility: Int
    public var fitConfidence: Int
    public var occasionCoverage: Int
    public var colorCohesion: Int
    public var wearUtilization: Int
    public var condition: Int
    public var redundancyControl: Int

    public init(
        overall: Int,
        versatility: Int,
        fitConfidence: Int,
        occasionCoverage: Int,
        colorCohesion: Int,
        wearUtilization: Int,
        condition: Int,
        redundancyControl: Int
    ) {
        self.overall = overall
        self.versatility = versatility
        self.fitConfidence = fitConfidence
        self.occasionCoverage = occasionCoverage
        self.colorCohesion = colorCohesion
        self.wearUtilization = wearUtilization
        self.condition = condition
        self.redundancyControl = redundancyControl
    }

    enum CodingKeys: String, CodingKey {
        case overall
        case versatility
        case fitConfidence = "fit_confidence"
        case occasionCoverage = "occasion_coverage"
        case colorCohesion = "color_cohesion"
        case wearUtilization = "wear_utilization"
        case condition
        case redundancyControl = "redundancy_control"
    }
}
