//
//  LiveClosetRepository+Scan.swift
//  AstraStyle
//
//  The scan half of `LiveClosetRepository`: upload, delete, analyze,
//  batch-analyze and the batch poll (P3-SCAN-05/07/08, spec §12, §14
//  `closet/*`).
//
//  Split out of `LiveClosetRepository.swift` when that type crossed
//  SwiftLint's `type_body_length` of 280 — a threshold `.swiftlint.yml`
//  sets from a measured maximum and whose header says to change it only
//  because the rule is wrong for this codebase, not because a violation is
//  inconvenient. It is not wrong here: the CRUD half answers "what is in
//  the closet" and this half answers "how does a photograph become a
//  garment", and they share nothing but the client handles.
//
//  Same pattern, and the same reason, as `ScannerReviewViewModel+Pipeline`.
//

import Foundation
import Supabase

extension LiveClosetRepository {
    private struct ScanUnlockCountResponse: Decodable, Sendable {
        let status: String
        let outfitsUnlocked: Int?

        enum CodingKeys: String, CodingKey {
            case status
            case outfitsUnlocked = "outfits_unlocked"
        }
    }

    public func fetchScanUnlockCount(savedItemID: UUID) async throws -> ScanUnlockCountResult {
        let response: ScanUnlockCountResponse = try await apiClient.send(
            .fetchScanUnlockCount(id: savedItemID),
            as: ScanUnlockCountResponse.self
        )
        switch response.status {
        case "available":
            guard let count = response.outfitsUnlocked, count >= 0 else {
                throw AstraError.server("The outfit count response was incomplete.")
            }
            return .count(count)
        case "unmeasurable":
            guard response.outfitsUnlocked == nil else {
                throw AstraError.server("The outfit count response was inconsistent.")
            }
            return .unmeasurable
        default:
            throw AstraError.server("The outfit count response was invalid.")
        }
    }

    /// The wire element both analyze endpoints take: the uploaded object's
    /// path plus the correlation id the server must echo back. Image bytes
    /// go to Storage, never into the JSON body (`docs/08` §2's
    /// `imageStoragePath`, "signed, private Supabase Storage path — never a
    /// public URL").
    struct AnalyzeRequestElement: Encodable, Sendable {
        let requestID: UUID
        let storagePath: String
        let imageType: ClosetImageType
        let deviceHints: GarmentDeviceHints?

        enum CodingKeys: String, CodingKey {
            case requestID = "request_id"
            case storagePath = "storage_path"
            case imageType = "image_type"
            case deviceHints = "device_hints"
        }
    }

    func uploadedElement(for request: ClosetItemAnalysisRequest) async throws -> AnalyzeRequestElement {
        let path: String
        if let existing = request.storagePath, !existing.isEmpty {
            path = existing
        } else {
            path = try await uploadCapturedImage(request.imageData)
        }
        return AnalyzeRequestElement(
            requestID: request.id,
            storagePath: path,
            imageType: request.imageType,
            deviceHints: request.deviceHints
        )
    }

    public func uploadCapturedImage(_ data: Data) async throws -> String {
        try await uploadCaptured(imageData: data)
    }

    public func uploadClosetCaptureImage(_ data: Data) async throws -> String {
        try await uploadCaptured(imageData: data, includeThumbnail: true)
    }

    public func uploadClosetCaptureImage(_ data: Data, requestID: UUID) async throws -> String {
        try await uploadCaptured(imageData: data, includeThumbnail: true, requestID: requestID)
    }

    public func deleteCapturedImage(atPath storagePath: String) async throws {
        let owner = await currentUserID()
        if GuestLocalImageStore.isLocal(storagePath) {
            try GuestLocalImageStore.delete(storagePath)
            return
        }
        let paths = [storagePath, ClosetImageVariantPaths.thumbnail(for: storagePath)].compactMap { $0 }
        do {
            _ = try await supabase.storage.from("user-content").remove(paths: paths)
            if let owner {
                for path in paths {
                    await ClosetImageByteCache.shared.remove(ownerID: owner, storagePath: path)
                }
            }
        } catch {
            throw AstraError.server("Couldn't remove that photo from your storage.")
        }
    }

    public func analyzeItem(_ request: ClosetItemAnalysisRequest) async throws -> ClosetItemAnalysisResult {
        // `AstraAPIClient` mints and retries under a stable Idempotency-Key
        // for `.analyzeClosetItem` — see that type's `requiresIdempotencyKey`
        // and HANDOFF §9.2. Do not wrap this call in a second retry loop.
        //
        // The compensating delete covers only the upload *this call* made.
        // A path the caller supplied belongs to the caller — the scanner
        // keeps its uploaded path across an analyze retry precisely so the
        // retry does not re-upload, and deleting it here would delete the
        // object out from under the retry that is about to use it.
        let uploadedHere = request.storagePath?.isEmpty != false
        let element = try await uploadedElement(for: request)
        if GuestLocalImageStore.isLocal(element.storagePath) {
            return ClosetItemAnalysisResult.guestLocalPlaceholder()
        }
        do {
            return try await apiClient.send(
                .analyzeClosetItem,
                body: element,
                as: ClosetItemAnalysisResult.self
            )
        } catch {
            if uploadedHere {
                try? await deleteCapturedImage(atPath: element.storagePath)
            }
            throw error
        }
    }

    public func batchAnalyzeItems(_ requests: [ClosetItemAnalysisRequest]) async throws -> ClosetItemAnalysisBatch {
        try await batchAnalyzeItems(requests, idempotencyKey: UUID().uuidString.lowercased())
    }

    public func batchAnalyzeItems(
        _ requests: [ClosetItemAnalysisRequest],
        idempotencyKey: String
    ) async throws -> ClosetItemAnalysisBatch {
        struct BatchRequest: Encodable, Sendable {
            let items: [AnalyzeRequestElement]
        }
        // Uploads run in submission order rather than concurrently on
        // purpose: the upload leg is bandwidth-bound on a phone, and firing
        // N image uploads at once on a weak connection makes every one of
        // them slower and the first result later. Analysis concurrency is
        // the server's job — and even there it is job+poll, one item per
        // status tick, so the interactive analyze-item path is not starved
        // (HANDOFF §9.3).
        var elements: [AnalyzeRequestElement] = []
        elements.reserveCapacity(requests.count)
        // Paths this call uploaded, so a failure part-way through a
        // twenty-image batch does not leave nineteen objects in the user's
        // storage that nothing will ever reference. Caller-supplied paths
        // are excluded for the same reason as the single-item path.
        var uploadedHere: [String] = []
        for request in requests {
            do {
                let element = try await uploadedElement(for: request)
                if request.storagePath?.isEmpty != false {
                    uploadedHere.append(element.storagePath)
                }
                elements.append(element)
            } catch {
                for path in uploadedHere {
                    try? await deleteCapturedImage(atPath: path)
                }
                throw error
            }
        }
        if elements.allSatisfy({ GuestLocalImageStore.isLocal($0.storagePath) }) {
            return ClosetItemAnalysisBatch(results: requests.map { request in
                ClosetItemAnalysisBatchItem(
                    id: request.id,
                    outcome: .analyzed(ClosetItemAnalysisResult.guestLocalPlaceholder())
                )
            })
        }
        let job: ClosetItemAnalysisBatchJob
        do {
            job = try await apiClient.send(
                .batchAnalyzeCloset,
                body: BatchRequest(items: elements),
                idempotencyKey: idempotencyKey,
                as: ClosetItemAnalysisBatchJob.self
            )
        } catch {
            let astra = batchAstraError(error)
            // The server might have accepted the request before the response
            // was lost, and the API client may have already retried the POST.
            // Even an HTTP rejection on the final attempt cannot prove that
            // no earlier attempt inserted the job. Keep deterministic uploads
            // so this key can replay or be safely cancelled.
            throw ClosetBatchAnalysisFailure.enqueueUncertain(astra)
        }
        // Polling sits outside the compensating scope on purpose: once the
        // job is enqueued the server owns those objects, and a poll that
        // times out is not a reason to delete images a job is still working
        // through.
        do {
            return try await pollBatchJob(id: job.jobID, expectedCount: requests.count)
        } catch let failure as ClosetBatchAnalysisFailure {
            throw failure
        } catch {
            throw ClosetBatchAnalysisFailure.accepted(
                jobID: job.jobID,
                underlying: batchAstraError(error)
            )
        }
    }

    public func resumeBatchAnalysis(
        _ requests: [ClosetItemAnalysisRequest],
        idempotencyKey: String,
        acceptedJobID: UUID?,
        isRetry: Bool
    ) async throws -> ClosetItemAnalysisBatch {
        _ = isRetry
        guard let acceptedJobID else {
            return try await batchAnalyzeItems(requests, idempotencyKey: idempotencyKey)
        }
        do {
            return try await pollBatchJob(id: acceptedJobID, expectedCount: requests.count)
        } catch let failure as ClosetBatchAnalysisFailure {
            throw failure
        } catch {
            throw ClosetBatchAnalysisFailure.accepted(
                jobID: acceptedJobID,
                underlying: batchAstraError(error)
            )
        }
    }

    public func cancelBatchAnalysis(idempotencyKey: String) async throws {
        struct CancelRequest: Encodable, Sendable {}
        struct CancelResponse: Decodable, Sendable {
            let cancelled: Bool
        }
        let response = try await apiClient.send(
            .cancelBatchAnalysis,
            body: CancelRequest(),
            idempotencyKey: idempotencyKey,
            as: CancelResponse.self
        )
        guard response.cancelled else {
            throw AstraError.server("The batch cancellation was not confirmed.")
        }
    }

    /// Polls `GET /closet/batch-status/:id` until the job is terminal.
    ///
    /// One item is advanced per server poll, so a 5-image batch needs at
    /// least five successful polls — that is intentional isolate sharing,
    /// not a client bug. Backoff grows gently so a brief generating gap
    /// does not hammer the function.
    func pollBatchJob(id: UUID, expectedCount: Int) async throws -> ClosetItemAnalysisBatch {
        var delayNanoseconds: UInt64 = 200_000_000 // 200ms
        let maxDelayNanoseconds: UInt64 = 2_000_000_000
        // Worst case: one advance per poll × item count, plus headroom for
        // transient generating states with no new result.
        let maxAttempts = max(expectedCount * 3, 6) + 10

        for _ in 0..<maxAttempts {
            let payload = try await apiClient.send(
                .batchAnalyzeClosetStatus(id: id),
                as: ClosetItemAnalysisBatchJobStatusPayload.self
            )
            if payload.status == .failed {
                throw ClosetBatchAnalysisFailure.terminalFailure(AstraError.server(
                    payload.errorMessage ?? "Batch analysis failed.",
                    requestID: nil
                ))
            }
            if payload.status.isTerminal {
                return payload.asBatch
            }
            try await Task.sleep(nanoseconds: delayNanoseconds)
            delayNanoseconds = min(delayNanoseconds * 2, maxDelayNanoseconds)
        }
        throw AstraError.server("Batch analysis timed out before completing.", requestID: nil)
    }

    private func batchAstraError(_ error: Error) -> AstraError {
        if let astra = error as? AstraError { return astra }
        return AstraError.network("That batch could not be analysed. Try again in a moment.")
    }

    // MARK: - Helpers

    /// Uploads one captured image and returns its storage path.
    ///
    /// Two things here are load-bearing and were both wrong before:
    ///
    /// 1. The bucket is `user-content`. There is exactly one bucket
    ///    (`20260728101000_storage_buckets.sql`) and it is not called
    ///    "closet" — `closet` is a folder *inside* it, which is the whole
    ///    point of the shared `users/{user_id}/...` prefix that migration
    ///    documents. Uploading to a nonexistent bucket fails outright.
    /// 2. The user id is lowercased. The four storage policies compare
    ///    `(storage.foldername(name))[2]` against `auth.uid()::text`, and
    ///    Postgres renders a uuid lowercase while Swift's
    ///    `UUID.uuidString` is UPPERCASE. Without `.lowercased()` the path
    ///    is well-formed, the bucket is right, and the insert is still
    ///    rejected by RLS — the most expensive kind of wrong, because it
    ///    looks correct in the debugger.
    ///
    /// The path has no `{closet_item_id}` segment (the migration's comment
    /// illustrates `users/{uid}/closet/{closet_item_id}/{image_id}.jpg`)
    /// because this runs during a scan, BEFORE the user has confirmed the
    /// analysis and a `ClosetItem` exists. Only segments [1] and [2] are
    /// policy-relevant, so this is a valid path under the same convention.
    func uploadCaptured(imageData: Data) async throws -> String {
        try await uploadCaptured(imageData: imageData, includeThumbnail: false)
    }

    private func uploadCaptured(
        imageData: Data,
        includeThumbnail: Bool,
        requestID: UUID? = nil
    ) async throws -> String {
        let format = try CapturedImageUploadFormat.detect(imageData)
        let thumbnailData = includeThumbnail
            ? try ClosetImageThumbnailer.thumbnailData(from: imageData)
            : nil
        do {
            let session = try await supabase.auth.session
            if session.user.isAnonymous {
                return try saveGuestCapture(
                    imageData,
                    thumbnailData: thumbnailData,
                    ownerID: session.user.id,
                    requestID: requestID
                )
            }
            let userID = session.user.id.uuidString.lowercased()
            let fileID = requestID?.uuidString.lowercased() ?? UUID().uuidString.lowercased()
            let folder = requestID == nil ? "closet" : "closet/batch"
            let path = "users/\(userID)/\(folder)/\(fileID).\(format.fileExtension)"
            return try await uploadRemoteCapture(
                imageData,
                thumbnailData: thumbnailData,
                format: format,
                path: path,
                ownerID: session.user.id,
                upsert: requestID != nil
            )
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.network("Couldn't upload that photo. Check your connection and try again.")
        }
    }

    private func saveGuestCapture(
        _ data: Data,
        thumbnailData: Data?,
        ownerID: UUID,
        requestID: UUID? = nil
    ) throws -> String {
        let path = try requestID.map { try GuestLocalImageStore.save(data, userID: ownerID, fileID: $0) }
            ?? GuestLocalImageStore.save(data, userID: ownerID)
        guard let thumbnailData else { return path }
        do {
            _ = try GuestLocalImageStore.saveThumbnail(thumbnailData, for: path, userID: ownerID)
            return path
        } catch {
            try? GuestLocalImageStore.delete(path)
            throw error
        }
    }

    private func uploadRemoteCapture(
        _ data: Data,
        thumbnailData: Data?,
        format: CapturedImageUploadFormat,
        path: String,
        ownerID: UUID,
        upsert: Bool = false
    ) async throws -> String {
        if let thumbnailData {
            let transport = ClosetCaptureUploadTransport(
                currentOwnerID: { await self.currentUserID() },
                uploadObject: { path, bytes, contentType in
                    _ = try await self.supabase.storage.from("user-content").upload(
                        path,
                        data: bytes,
                        options: FileOptions(contentType: contentType, upsert: upsert)
                    )
                },
                removeObjects: { paths in
                    _ = try? await self.supabase.storage.from("user-content").remove(paths: paths)
                }
            )
            return try await ClosetCaptureUploadPipeline.upload(
                ClosetCaptureUploadRequest(
                    sourceData: data,
                    thumbnailData: thumbnailData,
                    contentType: format.contentType,
                    sourcePath: path,
                    ownerID: ownerID
                ),
                transport: transport
            )
        }

        return try await uploadOriginalCapture(
            data,
            format: format,
            path: path,
            ownerID: ownerID,
            upsert: upsert
        )
    }

    private func uploadOriginalCapture(
        _ data: Data,
        format: CapturedImageUploadFormat,
        path: String,
        ownerID: UUID,
        upsert: Bool = false
    ) async throws -> String {
        do {
            _ = try await supabase.storage.from("user-content")
                .upload(path, data: data, options: FileOptions(contentType: format.contentType, upsert: upsert))
            try await requireSameOwner(as: ownerID)
            return path
        } catch {
            _ = try? await supabase.storage.from("user-content").remove(paths: [path])
            throw error
        }
    }

    private func requireSameOwner(as ownerID: UUID) async throws {
        guard try await supabase.auth.session.user.id == ownerID else {
            throw AstraError.auth("Your account changed while uploading that photo.")
        }
    }
}
