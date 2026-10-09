import Foundation

/// Narrow transport boundary for the two-object closet capture upload. The
/// same pipeline is used by the Supabase adapter and fake-transport tests.
struct ClosetCaptureUploadTransport: Sendable {
    let currentOwnerID: @Sendable () async -> UUID?
    let uploadObject: @Sendable (String, Data, String) async throws -> Void
    let removeObjects: @Sendable ([String]) async -> Void
}

struct ClosetCaptureUploadRequest: Sendable {
    let sourceData: Data
    let thumbnailData: Data
    let contentType: String
    let sourcePath: String
    let ownerID: UUID
}

enum ClosetCaptureUploadPipeline {
    static func upload(
        _ request: ClosetCaptureUploadRequest,
        transport: ClosetCaptureUploadTransport
    ) async throws -> String {
        guard ClosetImageByteCache.isOwnedClosetImagePath(request.sourcePath, ownerID: request.ownerID),
              let thumbnailPath = ClosetImageVariantPaths.thumbnail(for: request.sourcePath) else {
            throw AstraError.auth("That photo belongs to a different account or is unavailable.")
        }
        guard await transport.currentOwnerID() == request.ownerID else {
            throw AstraError.auth("Your account changed before that photo could upload.")
        }

        do {
            try await transport.uploadObject(request.sourcePath, request.sourceData, request.contentType)
            try await requireOwner(request.ownerID, transport: transport)
            try await transport.uploadObject(thumbnailPath, request.thumbnailData, request.contentType)
            try await requireOwner(request.ownerID, transport: transport)
            return request.sourcePath
        } catch {
            // Both deterministic keys were minted for this unique capture;
            // remove only those keys if either leg fails or the account flips.
            await transport.removeObjects([request.sourcePath, thumbnailPath])
            throw error
        }
    }

    private static func requireOwner(
        _ expected: UUID,
        transport: ClosetCaptureUploadTransport
    ) async throws {
        guard await transport.currentOwnerID() == expected else {
            throw AstraError.auth("Your account changed while uploading that photo.")
        }
    }
}
