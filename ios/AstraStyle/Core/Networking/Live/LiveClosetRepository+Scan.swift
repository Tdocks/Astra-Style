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

    public func deleteCapturedImage(atPath storagePath: String) async throws {
        if GuestLocalImageStore.isLocal(storagePath) {
            try GuestLocalImageStore.delete(storagePath)
            return
        }
        do {
            _ = try await supabase.storage.from("user-content").remove(paths: [storagePath])
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
        let job: ClosetItemAnalysisBatchJob
        do {
            for request in requests {
                let element = try await uploadedElement(for: request)
                if request.storagePath?.isEmpty != false {
                    uploadedHere.append(element.storagePath)
                }
                elements.append(element)
            }
            if elements.allSatisfy({ GuestLocalImageStore.isLocal($0.storagePath) }) {
                return ClosetItemAnalysisBatch(results: requests.map { request in
                    ClosetItemAnalysisBatchItem(
                        id: request.id,
                        outcome: .analyzed(ClosetItemAnalysisResult.guestLocalPlaceholder())
                    )
                })
            }
            job = try await apiClient.send(
                .batchAnalyzeCloset,
                body: BatchRequest(items: elements),
                as: ClosetItemAnalysisBatchJob.self
            )
        } catch {
            for path in uploadedHere {
                try? await deleteCapturedImage(atPath: path)
            }
            throw error
        }
        // Polling sits outside the compensating scope on purpose: once the
        // job is enqueued the server owns those objects, and a poll that
        // times out is not a reason to delete images a job is still working
        // through.
        return try await pollBatchJob(id: job.jobID, expectedCount: requests.count)
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
                throw AstraError.server(
                    payload.errorMessage ?? "Batch analysis failed.",
                    requestID: nil
                )
            }
            if payload.status.isTerminal {
                return payload.asBatch
            }
            try await Task.sleep(nanoseconds: delayNanoseconds)
            delayNanoseconds = min(delayNanoseconds * 2, maxDelayNanoseconds)
        }
        throw AstraError.server("Batch analysis timed out before completing.", requestID: nil)
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
        do {
            let session = try await supabase.auth.session
            if session.user.isAnonymous {
                return try GuestLocalImageStore.save(imageData, userID: session.user.id)
            }
            let userID = session.user.id.uuidString.lowercased()
            let path = "users/\(userID)/closet/\(UUID().uuidString.lowercased()).jpg"
            _ = try await supabase.storage
                .from("user-content")
                .upload(path, data: imageData, options: FileOptions(contentType: "image/jpeg"))
            return path
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.network("Couldn't upload that photo. Check your connection and try again.")
        }
    }
}
