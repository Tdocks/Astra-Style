//
//  ScannerReviewViewModel.swift
//  AstraStyle
//
//  Upload → analyze → editable review → save (P3-SCAN-05 / P3-SCAN-09).
//  Seeds fields from `ClosetItemAnalysisResult`, marks low-confidence via
//  `isLowConfidence(_:)`, and persists the user's corrections through
//  `createItem` — never the raw suggestions alone.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class ScannerReviewViewModel {

    public enum Phase: Equatable {
        case loading
        case uploading
        case analyzing
        case pendingAnalysis
        case ready
        case saving
        case saved
        case uploadFailed(AstraError)
        case analyzeFailed(AstraError)
        case queueFailed(AstraError)
        case saveFailed(AstraError)
        case capReached(limit: Int)
        case missingDraft

        public static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.uploading, .uploading), (.analyzing, .analyzing),
                 (.pendingAnalysis, .pendingAnalysis), (.ready, .ready), (.saving, .saving),
                 (.saved, .saved), (.missingDraft, .missingDraft):
                true
            case (.uploadFailed(let left), .uploadFailed(let right)),
                 (.analyzeFailed(let left), .analyzeFailed(let right)),
                 (.queueFailed(let left), .queueFailed(let right)),
                 (.saveFailed(let left), .saveFailed(let right)):
                left == right
            case (.capReached(let left), .capReached(let right)):
                left == right
            default:
                false
            }
        }
    }

    public enum UnlockCountState: Equatable, Sendable {
        case calculating
        case count(Int)
        case unavailable
        case unmeasurable
    }

    /// Bundles repository seams so `init` stays under SwiftLint's
    /// `function_parameter_count` (5) without dropping a real dependency.
    /// Not `Sendable`: `CaptureDraftStore` is `@MainActor` and this bundle
    /// is only constructed on the main actor at the review destination.
    public struct Dependencies {
        public let draftStore: CaptureDraftStore
        public let closetRepository: ClosetRepository
        public let imageURLResolver: ClosetImageURLResolving
        public let pendingScanQueue: PendingScanQueue
        public let scannerSaveJournal: ScannerSaveJournaling
        public let networkMonitor: NetworkReachabilityMonitoring
        public let analyticsClient: AnalyticsClient
        public let currentUserID: @Sendable () async -> UUID?

        public init(
            draftStore: CaptureDraftStore,
            closetRepository: ClosetRepository,
            imageURLResolver: ClosetImageURLResolving,
            pendingScanQueue: PendingScanQueue,
            scannerSaveJournal: ScannerSaveJournaling = InMemoryScannerSaveJournal(),
            networkMonitor: NetworkReachabilityMonitoring = SystemNetworkReachabilityMonitor(),
            analyticsClient: AnalyticsClient = NoOpAnalyticsClient(),
            currentUserID: @escaping @Sendable () async -> UUID?
        ) {
            self.draftStore = draftStore
            self.closetRepository = closetRepository
            self.imageURLResolver = imageURLResolver
            self.pendingScanQueue = pendingScanQueue
            self.scannerSaveJournal = scannerSaveJournal
            self.networkMonitor = networkMonitor
            self.analyticsClient = analyticsClient
            self.currentUserID = currentUserID
        }
    }

    // `internal(set)` so pipeline helpers in `ScannerReviewViewModel+Pipeline`
    // can mutate phase/paths without living in this file (type_body_length).
    public internal(set) var phase: Phase = .loading
    public private(set) var draftID: UUID
    public internal(set) var localPreviewData: Data?
    public internal(set) var signedPreviewURL: URL?
    public internal(set) var storagePath: String?
    var discardRequestedDuringSave = false
    var saveMayHavePersisted = false
    var cachedCutout: (source: String, path: String)?
    public internal(set) var analysis: ClosetItemAnalysisResult?
    public internal(set) var ocrText: String?
    /// Server-computed count after a successful save. Unavailable and
    /// unmeasurable remain distinct from a real zero.
    public internal(set) var unlockCountState: UnlockCountState = .calculating
    public var outfitsUnlockedCount: Int? {
        guard case .count(let count) = unlockCountState else { return nil }
        return count
    }

    /// The garment this flow created, once it exists.
    ///
    /// Exposed so a host that presented the scanner can learn what came back
    /// — onboarding's first-items step appends it to the list it is
    /// building. It is the repository's return value, not the locally-built
    /// draft, so anything the server normalised on write is what the caller
    /// sees rather than what was sent.
    public internal(set) var savedItem: ClosetItem?

    public var name: String = ""
    public var brand: String = ""
    public var category: ClothingCategory = .top
    public var subcategory: String = ""
    public var primaryColor: String = ""
    public var secondaryColorsText: String = ""
    public var pattern: GarmentPattern?
    public var materialText: String = ""
    public var size: String = ""
    public var fit: ItemFit?
    public var condition: ItemCondition?
    public var seasonality: Set<Season> = []
    public var formalityScoreText: String = ""
    public var warmthScoreText: String = ""
    public var waterResistanceScoreText: String = ""

    public var canSave: Bool {
        switch phase {
        case .ready, .saveFailed, .capReached: break
        default: return false
        }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var saveBlockedReason: String? {
        guard case .ready = phase else { return nil }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Add a name before saving.", comment: "Scanner review save blocked")
        }
        return nil
    }

    let draftStore: CaptureDraftStore
    let closetRepository: ClosetRepository
    let imageURLResolver: ClosetImageURLResolving
    let pendingScanQueue: PendingScanQueue
    let scannerSaveJournal: ScannerSaveJournaling
    let networkMonitor: NetworkReachabilityMonitoring
    let analyticsClient: AnalyticsClient
    let currentUserID: @Sendable () async -> UUID?
    var originalSuggestions: ClosetItemAnalysisResult?
    @ObservationIgnored var saveIdentities: [UUID: (item: UUID, image: UUID)] = [:]
    @ObservationIgnored var connectivityTask: Task<Void, Never>?

    public init(draftID: UUID, dependencies: Dependencies) {
        self.draftID = draftID
        self.draftStore = dependencies.draftStore
        self.closetRepository = dependencies.closetRepository
        self.imageURLResolver = dependencies.imageURLResolver
        self.pendingScanQueue = dependencies.pendingScanQueue
        self.scannerSaveJournal = dependencies.scannerSaveJournal
        self.networkMonitor = dependencies.networkMonitor
        self.analyticsClient = dependencies.analyticsClient
        self.currentUserID = dependencies.currentUserID
    }

    deinit {
        connectivityTask?.cancel()
    }

    public func start() async {
        startConnectivityObservation()
        guard let draft = draftStore.draft(id: draftID) else {
            phase = .missingDraft
            return
        }
        localPreviewData = draft.prepared.data
        storagePath = draft.storagePath
        signedPreviewURL = draft.signedPreviewURL
        if let analysis = draft.analysis {
            applyAnalysis(analysis)
            phase = .ready
            return
        }

        if storagePath == nil {
            if await networkMonitor.isOffline() {
                await enqueuePendingAnalysis(data: draft.prepared.data, deviceHints: draft.deviceHints)
                return
            }
            if let error = await upload(data: draft.prepared.data) {
                if shouldQueueForReconnect(error) {
                    await enqueuePendingAnalysis(data: draft.prepared.data, deviceHints: draft.deviceHints)
                }
                return
            }
        } else {
            phase = .analyzing
        }
        if let error = await analyze(imageData: draft.prepared.data), shouldQueueForReconnect(error) {
            await enqueuePendingAnalysis(data: draft.prepared.data, deviceHints: draft.deviceHints)
        }
    }

    public func retryUpload() async {
        guard let data = localPreviewData else { return }
        if let error = await upload(data: data) {
            if shouldQueueForReconnect(error) {
                await enqueuePendingAnalysis(data: data, deviceHints: draftStore.draft(id: draftID)?.deviceHints)
            }
            return
        }
        guard case .analyzing = phase else { return }
        if let error = await analyze(imageData: data), shouldQueueForReconnect(error) {
            await enqueuePendingAnalysis(data: data, deviceHints: draftStore.draft(id: draftID)?.deviceHints)
        }
    }

    public func retryAnalyze() async {
        guard let data = localPreviewData else { return }
        phase = .analyzing
        if let error = await analyze(imageData: data), shouldQueueForReconnect(error) {
            await enqueuePendingAnalysis(data: data, deviceHints: draftStore.draft(id: draftID)?.deviceHints)
        }
    }

    /// Cuts the garment out of its background and uploads the result, or
    /// returns nil and lets the raw photograph stand.
    ///
    /// Runs at save rather than at analyse, deliberately: a garment the user
    /// abandons on the review screen never costs a second upload, and by the
    /// time he taps Save the bytes are already in memory.
    ///
    /// Every failure here is nil, never a thrown error. A man who has just
    /// corrected six fields and pressed Save must not be told his garment
    /// could not be saved because a cosmetic pass on the photograph did not
    /// work — `displayStoragePath` falls back to the capture on its own, and
    /// he will see the photograph he took, which is what he would have seen
    /// anyway.
    ///
    /// The cut-out is produced even when the closet is set to display raw
    /// photographs. It is cheap, it is local, and storing it means turning
    /// the setting back on is instant instead of a re-scan of the whole
    /// wardrobe.
    func uploadedCutoutPath() async -> String? {
        if let cachedCutout, cachedCutout.source == storagePath { return cachedCutout.path }
        guard let data = localPreviewData else { return nil }
        // Off the main actor: this is a Vision request and a full-frame
        // re-encode, and the review screen is on screen while it runs.
        let cutout = await Task.detached(priority: .userInitiated) {
            BackgroundRemoval.cutout(from: data)
        }.value
        return await persistCutoutOrFallback(cutout)
    }

    /// Removes the uploaded capture when the user leaves without saving.
    ///
    /// `uploadCapturedImage` puts bytes in `user-content` before the user
    /// has decided anything. Retake, Close and a swipe-dismiss all end the
    /// flow without a `ClosetItemImage` ever referencing that path, so
    /// without this the object stays there permanently: nothing in Postgres
    /// points at it, nothing in the app can show it, and it counts against
    /// his storage. A batch leaves one per image.
    ///
    /// Three properties this deliberately has:
    ///
    /// - **It is a no-op after `.saved`.** A saved item's
    ///   `ClosetItemImage.storagePath` is that exact path; deleting it
    ///   would blank the garment he just added.
    /// - **It clears `storagePath` first**, so a second call (Retake then
    ///   Close, say) cannot ask the server to delete the same object twice.
    /// - **It swallows the failure.** A cleanup that cannot reach the
    ///   network must not trap the user on a screen he is trying to leave.
    ///   The leak is logged so it is a known number rather than an
    ///   invisible one; nothing about the flow depends on the result.
    public func discardUnsavedUpload() async {
        if phase == .saving { discardRequestedDuringSave = true; return }
        // A lost database response may have committed; retain photos until reconciliation.
        guard !saveMayHavePersisted else { return }
        guard phase != .saved, let path = storagePath else { return }
        storagePath = nil
        let cutoutPath = cachedCutout?.path
        cachedCutout = nil
        if var draft = draftStore.draft(id: draftID) {
            draft.storagePath = nil
            draft.signedPreviewURL = nil
            draftStore.update(draft)
        }
        for pendingPath in Set([path] + (cutoutPath.map { [$0] } ?? [])) {
            do {
                try await closetRepository.deleteCapturedImage(atPath: pendingPath)
            } catch {
                Self.logger.error("Abandoned scan photo cleanup failed.")
            }
        }
    }

    private static let logger = Logger(subsystem: "app.astrastyle", category: "scanner")

    public func isLowConfidence(_ field: AnalysisField) -> Bool {
        analysis?.isLowConfidence(field) ?? false
    }

    public func lowConfidenceFootnote(_ field: AnalysisField) -> String? {
        guard isLowConfidence(field) else { return nil }
        return String(localized: "Kyra isn’t sure — check this.",
                      comment: "Low-confidence field footnote on scan review")
    }
}

extension ScannerReviewViewModel {
    func finishSaveCleanup() async {
        if discardRequestedDuringSave {
            discardRequestedDuringSave = false
            await discardUnsavedUpload()
        }
    }

    func persistCutoutOrFallback(_ cutout: Data?) async -> String? {
        guard let source = storagePath else { return nil }
        if let cachedCutout, cachedCutout.source == source { return cachedCutout.path }
        let result: String?
        if let cutout {
            // Upload failure of a usable device mask is not segmentation failure.
            result = try? await closetRepository.uploadClosetCaptureImage(cutout)
        } else if !GuestLocalImageStore.isLocal(source) {
            result = try? await closetRepository.removeBackground(storagePath: source)
        } else {
            return nil
        }
        guard let result else { return nil }
        guard storagePath == source else {
            try? await closetRepository.deleteCapturedImage(atPath: result)
            return nil
        }
        cachedCutout = (source, result)
        return result
    }
}
