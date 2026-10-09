//
//  ScannerBatchViewModel.swift
//  AstraStyle
//
//  P3-SCAN-08's missing half.
//
//  The durable job table, `POST /closet/batch-analyze`, the polling
//  `batch-status` endpoint, `ClosetRepository.batchAnalyzeItems`, its live
//  implementation with compensating deletes, the mock, and the free-tier
//  wrapper all shipped. Nothing ever called any of it: no View and no
//  ViewModel referenced `batchAnalyzeItems`, and `ScannerRoute.batchCloset`
//  rendered a placeholder that said so out loud. A whole feature with no
//  door into it.
//
//  This is the door. Multi-select import → prepare each → upload each →
//  one batch analysis → a pre-analysed `CaptureDraft` per garment.
//
//  Review is deliberately NOT a new screen. `ScannerReviewViewModel.start()`
//  already short-circuits to `.ready` when the draft it loads carries an
//  analysis, so the batch walks the user through the existing single-item
//  review one garment at a time. That reuses the editable form, the
//  low-confidence marking and the save path rather than growing a second
//  copy of all three — and the review step is where a scan's labels get
//  corrected, which is the part of a twenty-garment session that is worth
//  the user's attention.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class ScannerBatchViewModel {

    public enum Phase: Equatable {
        case idle
        /// Local work: decode, resize, strip metadata, device hints.
        case preparing(done: Int, total: Int)
        /// Sequential uploads. Deliberately not concurrent — see `uploadAll`.
        case uploading(done: Int, total: Int)
        /// One submission, then polling. The server advances one item per
        /// poll, so this is the long phase and it has no per-item progress
        /// to report from the client side.
        case analyzing(total: Int)
        case ready(Outcome)
        case failed(AstraError)
        case capReached(limit: Int)
    }

    /// What a batch actually produced, including what it lost.
    ///
    /// Every count here exists because the alternative is a screen that says
    /// "12 garments ready" after being handed 15. A batch that quietly drops
    /// three photographs is the confounded reading this repo keeps refusing
    /// to ship: the user would find out by noticing an absence, weeks later,
    /// and have no way to tell which three.
    public struct Outcome: Equatable, Sendable {
        /// Draft ids in submission order, ready to walk through review.
        public var draftIDs: [UUID]
        /// Chosen but over `BatchScanLimits.maxItemsPerBatch`.
        public var skippedOverLimit: Int
        /// Chosen, but the photo library never handed over the bytes.
        /// Usually an image that lives in iCloud and is not on the device.
        /// Distinct from `unreadable`: nothing was ever looked at.
        public var couldNotLoad: Int
        /// Chosen but not decodable as an image.
        public var unreadable: Int
        /// Decoded fine, but the upload failed. Distinct from an analysis
        /// failure: the analyser never saw this photo, so saying anything
        /// about the photograph itself would be inventing a diagnosis.
        public var uploadFailed: Int
        /// Uploaded fine, but the analyser could not read them.
        public var analysisFailures: [ClosetItemAnalysisFailureReason: Int]
        /// Everything the user picked, before any of the above.
        public var selected: Int

        public var readyCount: Int { draftIDs.count }
        public var lostCount: Int { selected - readyCount }
        public var isCompletelyClean: Bool { lostCount == 0 }

        public init(
            draftIDs: [UUID] = [],
            skippedOverLimit: Int = 0,
            couldNotLoad: Int = 0,
            unreadable: Int = 0,
            uploadFailed: Int = 0,
            analysisFailures: [ClosetItemAnalysisFailureReason: Int] = [:],
            selected: Int = 0
        ) {
            self.draftIDs = draftIDs
            self.skippedOverLimit = skippedOverLimit
            self.couldNotLoad = couldNotLoad
            self.unreadable = unreadable
            self.uploadFailed = uploadFailed
            self.analysisFailures = analysisFailures
            self.selected = selected
        }
    }

    /// Bundles seams so `init` stays under SwiftLint's
    /// `function_parameter_count` (5), and so a test can drive the whole
    /// flow with bytes that are not a real JPEG. Not `Sendable`:
    /// `CaptureDraftStore` is `@MainActor` and this is only built there —
    /// the same reasoning as `ScannerReviewViewModel.Dependencies`.
    public struct Dependencies {
        public let draftStore: CaptureDraftStore
        public let closetRepository: ClosetRepository
        public let currentOwnerID: @Sendable () async -> UUID?
        public let pendingStore: any ScannerBatchPendingStoring
        /// Defaults to the shipping pipeline. Injected because
        /// `CapturePreparation` needs genuinely decodable image bytes and a
        /// unit test should not have to carry a JPEG fixture to exercise
        /// ordering, cancellation and failure accounting.
        public let prepare: (Data) throws -> CapturePreparation.Prepared
        /// Device-side region / OCR / colour, or nil when the bytes cannot
        /// be re-decoded. Absent hints are a real state the server handles;
        /// they are not an error.
        public let deviceHints: (Data) -> GarmentDeviceHints?

        public init(
            draftStore: CaptureDraftStore,
            closetRepository: ClosetRepository,
            currentOwnerID: @escaping @Sendable () async -> UUID? = { nil },
            pendingStore: any ScannerBatchPendingStoring = InMemoryScannerBatchPendingStore(),
            prepare: @escaping (Data) throws -> CapturePreparation.Prepared = {
                try CapturePreparation.prepareForUpload($0)
            },
            deviceHints: @escaping (Data) -> GarmentDeviceHints? = {
                ScannerBatchViewModel.liveDeviceHints(from: $0)
            }
        ) {
            self.draftStore = draftStore
            self.closetRepository = closetRepository
            self.currentOwnerID = currentOwnerID
            self.pendingStore = pendingStore
            self.prepare = prepare
            self.deviceHints = deviceHints
        }
    }

    /// Every loss is logged with its reason as PUBLIC text.
    ///
    /// `Logger`'s default is to redact interpolated values, which is right
    /// for anything describing a garment or a person and wrong for this: a
    /// failure category is not personal data, and redacting it meant the
    /// device log said `<private>` exactly where the answer was. Diagnosing
    /// a scan that failed on a real phone cost several rounds of guessing
    /// because of it. Nothing here interpolates a filename, a storage path
    /// or anything about the garment — only which of a fixed set of things
    /// went wrong, and how many times.
    static let logger = Logger(subsystem: "app.astrastyle", category: "scanner.batch")

    public internal(set) var phase: Phase = .idle

    let dependencies: Dependencies
    var pendingBatch: PendingBatch?
    var consumptionWrites: [UUID: Task<Bool, Never>] = [:]

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// True while the flow owns uploaded objects the user has not yet seen.
    /// The destination view uses this to keep Close from stranding them.
    public var isWorking: Bool {
        switch phase {
        case .preparing, .uploading, .analyzing:
            true
        case .idle, .ready, .failed, .capReached:
            false
        }
    }

    /// A failed request can still have an accepted server job. Keep its
    /// uploaded paths and stable key so Retry resumes that job rather than
    /// uploading the same photos again.
    public var canRetryPendingBatch: Bool { pendingBatch?.isComplete == false }
    public var hasPendingBatch: Bool { pendingBatch != nil }

    public func retryPendingBatch() async {
        guard let pendingBatch, !pendingBatch.isComplete else { return }
        var outcome = pendingBatch.outcome
        await analyzeAll(
            pendingBatch.uploaded,
            idempotencyKey: pendingBatch.idempotencyKey,
            acceptedJobID: pendingBatch.acceptedJobID,
            isRetry: true,
            outcome: &outcome
        )
    }

    struct Candidate {
        let id: UUID
        let capture: PreparedCapture
    }

    struct Uploaded {
        let id: UUID
        let capture: PreparedCapture
        let storagePath: String
        var analysis: ClosetItemAnalysisResult?
        var analysisFailureReason: ClosetItemAnalysisFailureReason?
    }

    struct PendingBatch {
        let uploaded: [Uploaded]
        let idempotencyKey: String
        let outcome: Outcome
        let ownerID: UUID
        var acceptedJobID: UUID?
        var isComplete: Bool
        var consumedDraftIDs: Set<UUID>
        var discardedDraftIDs: Set<UUID>

        init(
            uploaded: [Uploaded],
            idempotencyKey: String,
            outcome: Outcome,
            ownerID: UUID,
            acceptedJobID: UUID?,
            isComplete: Bool = false,
            consumedDraftIDs: Set<UUID> = [],
            discardedDraftIDs: Set<UUID> = []
        ) {
            self.uploaded = uploaded
            self.idempotencyKey = idempotencyKey
            self.outcome = outcome
            self.ownerID = ownerID
            self.acceptedJobID = acceptedJobID
            self.isComplete = isComplete
            self.consumedDraftIDs = consumedDraftIDs
            self.discardedDraftIDs = discardedDraftIDs
        }
    }

    func prepareAll(_ images: [Data], outcome: inout Outcome) -> [Candidate] {
        phase = .preparing(done: 0, total: images.count)
        var candidates: [Candidate] = []
        candidates.reserveCapacity(images.count)

        for (index, data) in images.enumerated() {
            // A photo the pipeline cannot decode is counted, not thrown.
            // One unreadable screenshot in a roll of twenty garments must
            // cost the user that screenshot, which is the same bargain
            // `batchAnalyzeItems` makes on the server side.
            if let ready = try? dependencies.prepare(data) {
                candidates.append(Candidate(
                    id: UUID(),
                    capture: PreparedCapture(
                        prepared: ready,
                        deviceHints: dependencies.deviceHints(ready.data)
                    )
                ))
            } else {
                outcome.unreadable += 1
            }
            phase = .preparing(done: index + 1, total: images.count)
        }
        return candidates
    }

    /// Uploads in submission order rather than concurrently, matching
    /// `LiveClosetRepository.batchAnalyzeItems`'s own reasoning: the upload
    /// leg is bandwidth-bound on a phone, and firing twenty at once makes
    /// every one of them slower and the first result later.
    ///
    func uploadAll(_ candidates: [Candidate], outcome: inout Outcome) async -> [Uploaded] {
        phase = .uploading(done: 0, total: candidates.count)
        var uploaded: [Uploaded] = []
        uploaded.reserveCapacity(candidates.count)

        for (index, candidate) in candidates.enumerated() {
            do {
                let path = try await dependencies.closetRepository
                    .uploadClosetCaptureImage(candidate.capture.prepared.data, requestID: candidate.id)
                uploaded.append(Uploaded(
                    id: candidate.id,
                    capture: candidate.capture,
                    storagePath: path
                ))
            } catch {
                // One image failing to upload costs the user that image,
                // not the batch — the same bargain the server's batch makes.
                //
                // Counted as `uploadFailed`, NOT as `.imageUnusable`, which
                // is what this used to do. `.imageUnusable` renders as "too
                // blurry or too dark to read" — a statement about the
                // photograph, made about a photograph the analyser never
                // received. A network failure described as a bad photo sends
                // the user to retake a picture that was fine.
                outcome.uploadFailed += 1
            }
            phase = .uploading(done: index + 1, total: candidates.count)
        }
        return uploaded
    }

}
