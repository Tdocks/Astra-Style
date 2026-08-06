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
        case saveFailed(AstraError)
        case missingDraft

        public static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.uploading, .uploading), (.analyzing, .analyzing),
                 (.pendingAnalysis, .pendingAnalysis), (.ready, .ready), (.saving, .saving),
                 (.saved, .saved), (.missingDraft, .missingDraft):
                true
            case (.uploadFailed(let left), .uploadFailed(let right)),
                 (.analyzeFailed(let left), .analyzeFailed(let right)),
                 (.saveFailed(let left), .saveFailed(let right)):
                left == right
            default:
                false
            }
        }
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
        public let networkMonitor: NetworkReachabilityMonitoring
        public let analyticsClient: AnalyticsClient
        public let currentUserID: @Sendable () async -> UUID?

        public init(
            draftStore: CaptureDraftStore,
            closetRepository: ClosetRepository,
            imageURLResolver: ClosetImageURLResolving,
            pendingScanQueue: PendingScanQueue,
            networkMonitor: NetworkReachabilityMonitoring = SystemNetworkReachabilityMonitor(),
            analyticsClient: AnalyticsClient = NoOpAnalyticsClient(),
            currentUserID: @escaping @Sendable () async -> UUID?
        ) {
            self.draftStore = draftStore
            self.closetRepository = closetRepository
            self.imageURLResolver = imageURLResolver
            self.pendingScanQueue = pendingScanQueue
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
    public internal(set) var analysis: ClosetItemAnalysisResult?
    public internal(set) var ocrText: String?
    /// Phase-3 simplified unlock count after a successful save (P3-SCAN-11).
    /// `nil` until save completes; zero is a real answer ("nothing new yet").
    public internal(set) var outfitsUnlockedCount: Int?

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
        guard case .ready = phase else { return false }
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
    let networkMonitor: NetworkReachabilityMonitoring
    let analyticsClient: AnalyticsClient
    let currentUserID: @Sendable () async -> UUID?
    var originalSuggestions: ClosetItemAnalysisResult?
    @ObservationIgnored var connectivityTask: Task<Void, Never>?

    public init(draftID: UUID, dependencies: Dependencies) {
        self.draftID = draftID
        self.draftStore = dependencies.draftStore
        self.closetRepository = dependencies.closetRepository
        self.imageURLResolver = dependencies.imageURLResolver
        self.pendingScanQueue = dependencies.pendingScanQueue
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

    public func save() async {
        guard canSave else { return }
        guard let storagePath else {
            phase = .saveFailed(AstraError.validation(
                String(localized: "The photo is not uploaded yet. Try again.",
                       comment: "Scanner save without storage path")
            ))
            return
        }
        guard let userID = await currentUserID() else {
            phase = .saveFailed(AstraError.auth(
                String(localized: "Sign in to save this piece to your closet.",
                       comment: "Scanner save without session")
            ))
            return
        }

        phase = .saving
        let itemID = UUID()
        let item = buildItem(id: itemID, userID: userID)
        let image = ClosetItemImage(
            id: UUID(),
            closetItemID: itemID,
            imageType: .front,
            storagePath: storagePath,
            backgroundRemovedPath: analysis?.normalizedImagePath,
            isPrimary: true
        )

        do {
            _ = try await closetRepository.createItem(item, images: [image])
            let corrected = fieldsCorrectedCount()
            analyticsClient.log(.closetItemAdded(category: item.category, source: .scan))
            if corrected > 0 {
                analyticsClient.log(.scanCorrected(fieldsCorrectedCount: corrected))
            }
            // P3-SCAN-11: complementary partners already owned, not the
            // Phase-4 purchase-unlock algorithm. Fail closed to 0 if the
            // closet cannot be read — never invent a marketing number.
            let closet = (try? await closetRepository.fetchItems()) ?? []
            outfitsUnlockedCount = ScanOutfitUnlockEstimator.newlyUnlockedCount(
                adding: item,
                to: closet
            )
            draftStore.remove(id: draftID)
            AstraHaptics.success()
            phase = .saved
        } catch {
            let astra = (error as? AstraError) ?? AstraError.server(
                String(localized: "Couldn't save that piece. Try again.",
                       comment: "Scanner save failure")
            )
            phase = .saveFailed(astra)
        }
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
        guard phase != .saved, let path = storagePath else { return }
        storagePath = nil
        if var draft = draftStore.draft(id: draftID) {
            draft.storagePath = nil
            draft.signedPreviewURL = nil
            draftStore.update(draft)
        }
        do {
            try await closetRepository.deleteCapturedImage(atPath: path)
        } catch {
            Self.logger.error("Abandoned scan capture left in storage: \(error.localizedDescription, privacy: .public)")
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
