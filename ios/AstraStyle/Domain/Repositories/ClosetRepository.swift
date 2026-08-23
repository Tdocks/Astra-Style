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

    /// Uploads prepared capture bytes to `user-content` and returns the
    /// storage path (P3-SCAN-05). Split from `analyzeItem` so a failed
    /// analysis retry does not re-upload (and so upload failure can be
    /// retried without discarding the local draft).
    func uploadCapturedImage(_ data: Data) async throws -> String

    /// Deletes a capture that was uploaded but never became a
    /// `ClosetItemImage` — a scan the user retook, closed out of, or whose
    /// analysis failed for good.
    ///
    /// Without this the bytes stay in `user-content` forever with nothing
    /// in Postgres referencing them: invisible to the user, invisible in
    /// the app, and counted against his storage. A batch leaks one per
    /// image. ADR 0010 defines a 24-hour sweep for *reference* photos and
    /// nothing at all for closet captures, and a sweep would in any case
    /// leave a photograph he abandoned on the server for a day.
    ///
    /// **Only ever called for a path that is not referenced by a saved
    /// item.** Deleting is not undoable, so the decision of when a capture
    /// is abandoned belongs to the flow that owns it
    /// (`ScannerReviewViewModel.discardUnsavedUpload`), not here.
    ///
    /// Throwing is meaningful — a caller that is cleaning up should not
    /// fail the user's action over it, but it should not pretend the
    /// object is gone either.
    func deleteCapturedImage(atPath storagePath: String) async throws

    /// Returns the server's analysis suggestion for review (spec §6.16
    /// "Review screen"). Does not create a `ClosetItem` by itself — call
    /// `createItem` once the user confirms.
    ///
    /// When `request.storagePath` is already set (from
    /// `uploadCapturedImage`), the upload leg is skipped. Takes the same
    /// request type as the batch call so that a single scan and one
    /// element of a batch scan share one element schema.
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

    /// After anonymous → Apple/email link, copy `guest-local/` photos into
    /// `user-content` and rewrite `closet_item_images.storage_path`.
    /// Default is a no-op so test doubles do not have to care.
    func migrateGuestLocalImages() async throws
}

extension ClosetRepository {
    public func migrateGuestLocalImages() async throws {}
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
