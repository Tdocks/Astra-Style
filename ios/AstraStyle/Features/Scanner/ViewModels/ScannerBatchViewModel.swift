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
        /// Chosen but not decodable as an image.
        public var unreadable: Int
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
            unreadable: Int = 0,
            analysisFailures: [ClosetItemAnalysisFailureReason: Int] = [:],
            selected: Int = 0
        ) {
            self.draftIDs = draftIDs
            self.skippedOverLimit = skippedOverLimit
            self.unreadable = unreadable
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
            prepare: @escaping (Data) throws -> CapturePreparation.Prepared = {
                try CapturePreparation.prepareForUpload($0)
            },
            deviceHints: @escaping (Data) -> GarmentDeviceHints? = {
                ScannerBatchViewModel.liveDeviceHints(from: $0)
            }
        ) {
            self.draftStore = draftStore
            self.closetRepository = closetRepository
            self.prepare = prepare
            self.deviceHints = deviceHints
        }
    }

    public private(set) var phase: Phase = .idle

    private let dependencies: Dependencies

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

    // MARK: - The flow

    public func importImages(_ images: [Data]) async {
        guard !images.isEmpty else { return }

        let selected = images.count
        let accepted = Array(images.prefix(BatchScanLimits.maxItemsPerBatch))
        var outcome = Outcome(
            skippedOverLimit: selected - accepted.count,
            selected: selected
        )

        let prepared = prepareAll(accepted, outcome: &outcome)
        guard !prepared.isEmpty else {
            phase = .ready(outcome)
            return
        }

        let uploaded = await uploadAll(prepared, outcome: &outcome)
        guard !uploaded.isEmpty else {
            phase = .ready(outcome)
            return
        }

        await analyzeAll(uploaded, outcome: &outcome)
    }

    // MARK: - Stages

    private struct Candidate {
        let id: UUID
        let capture: PreparedCapture
    }

    private struct Uploaded {
        let id: UUID
        let capture: PreparedCapture
        let storagePath: String
    }

    private func prepareAll(_ images: [Data], outcome: inout Outcome) -> [Candidate] {
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
    private func uploadAll(_ candidates: [Candidate], outcome: inout Outcome) async -> [Uploaded] {
        phase = .uploading(done: 0, total: candidates.count)
        var uploaded: [Uploaded] = []
        uploaded.reserveCapacity(candidates.count)

        for (index, candidate) in candidates.enumerated() {
            do {
                let path = try await dependencies.closetRepository
                    .uploadCapturedImage(candidate.capture.prepared.data)
                uploaded.append(Uploaded(
                    id: candidate.id,
                    capture: candidate.capture,
                    storagePath: path
                ))
            } catch {
                // One image failing to upload costs the user that image.
                // Counted as unusable rather than thrown, for the same
                // reason the server's batch does not fail wholesale on one
                // bad item.
                outcome.analysisFailures[.imageUnusable, default: 0] += 1
            }
            phase = .uploading(done: index + 1, total: candidates.count)
        }
        return uploaded
    }

    private func analyzeAll(_ uploaded: [Uploaded], outcome: inout Outcome) async {
        phase = .analyzing(total: uploaded.count)

        let requests = uploaded.map { item in
            ClosetItemAnalysisRequest(
                id: item.id,
                imageData: item.capture.prepared.data,
                // Supplying the path makes the repository skip its own
                // upload — and, more to the point, is the only way this
                // flow learns where each image landed. `batchAnalyzeItems`
                // returns analyses keyed by request id and nothing else, so
                // a caller that let it upload would have no storage path to
                // build a `ClosetItemImage` from and could never save what
                // it had just paid to analyse.
                storagePath: item.storagePath,
                imageType: .front,
                deviceHints: item.capture.deviceHints
            )
        }

        let batch: ClosetItemAnalysisBatch
        do {
            batch = try await dependencies.closetRepository.batchAnalyzeItems(requests)
        } catch let error as FreeTierClosetError {
            await discard(uploaded.map(\.storagePath))
            phase = capPhase(for: error)
            return
        } catch {
            await discard(uploaded.map(\.storagePath))
            phase = .failed(asAstraError(error))
            return
        }

        var strandedPaths: [String] = []
        for item in uploaded {
            if let analysis = batch.result(for: item.id) {
                dependencies.draftStore.put(CaptureDraft(
                    id: item.id,
                    prepared: item.capture.prepared,
                    deviceHints: item.capture.deviceHints,
                    storagePath: item.storagePath,
                    analysis: analysis
                ))
                outcome.draftIDs.append(item.id)
            } else {
                let reason = batch.failure(for: item.id)?.reason ?? .unknown
                outcome.analysisFailures[reason, default: 0] += 1
                // No draft will ever reference this object. Leaving it
                // costs the user storage for a garment they never got.
                strandedPaths.append(item.storagePath)
            }
        }
        await discard(strandedPaths)

        phase = .ready(outcome)
    }

    // MARK: - Helpers

    private func capPhase(for error: FreeTierClosetError) -> Phase {
        switch error {
        case .capReached(let limit):
            .capReached(limit: limit)
        }
    }

    /// Best-effort cleanup. A delete that fails is not worth failing the
    /// user's batch over, but it is worth attempting for every path rather
    /// than stopping at the first refusal.
    private func discard(_ paths: [String]) async {
        for path in paths {
            try? await dependencies.closetRepository.deleteCapturedImage(atPath: path)
        }
    }

    private func asAstraError(_ error: Error) -> AstraError {
        if let astra = error as? AstraError { return astra }
        return AstraError.network(String(
            localized: "That batch could not be analysed. Try again in a moment.",
            comment: "Scanner batch analysis failure"
        ))
    }
}
