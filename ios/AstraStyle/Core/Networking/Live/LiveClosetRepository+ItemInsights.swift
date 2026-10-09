import Foundation
import Supabase

extension LiveClosetRepository {
    public func fetchItemInsights(id: UUID) async throws -> ClosetItemInsights {
        try await apiClient.send(.fetchItemInsights(id: id), as: ClosetItemInsights.self)
    }
}

extension LiveClosetRepository {
    public func removeBackground(storagePath: String) async throws -> String? {
        let session = try await supabase.auth.session
        guard !session.user.isAnonymous, !GuestLocalImageStore.isLocal(storagePath) else { return nil }
        struct Body: Encodable, Sendable {
            let storagePath: String
            let deviceAdequate = false
            enum CodingKeys: String, CodingKey {
                case storagePath = "storage_path"
                case deviceAdequate = "device_adequate"
            }
        }
        struct Result: Decodable, Sendable {
            let backgroundRemovedPath: String?
            enum CodingKeys: String, CodingKey { case backgroundRemovedPath = "background_removed_path" }
        }
        let expected = try ClosetCutoutPath.expectedOutput(source: storagePath, owner: session.user.id)
        let result = try await apiClient.send(.removeClosetBackground,
                                               body: Body(storagePath: storagePath), as: Result.self)
        guard try await supabase.auth.session.user.id == session.user.id else {
            throw AstraError.auth("Your account changed while processing this photo.")
        }
        guard let path = result.backgroundRemovedPath else { return nil }
        guard path == expected else { throw AstraError.server("That cutout is unavailable.") }
        guard let thumbnailPath = ClosetImageVariantPaths.thumbnail(for: path) else {
            _ = try? await supabase.storage.from("user-content").remove(paths: [path])
            return nil
        }
        do {
            let cutoutBytes = try await supabase.storage.from("user-content").download(path: path)
            guard try await supabase.auth.session.user.id == session.user.id else {
                throw AstraError.auth("Your account changed while preparing that photo.")
            }
            let thumbnailBytes = try ClosetImageThumbnailer.thumbnailData(from: cutoutBytes)
            _ = try await supabase.storage.from("user-content").upload(
                thumbnailPath,
                data: thumbnailBytes,
                options: FileOptions(contentType: "image/png", upsert: true)
            )
            guard try await supabase.auth.session.user.id == session.user.id else {
                throw AstraError.auth("Your account changed while preparing that photo.")
            }
        } catch {
            // Server-produced cutouts are optional presentation assets. Do not
            // keep one whose small display variant could not be verified.
            _ = try? await supabase.storage.from("user-content").remove(paths: [path, thumbnailPath])
            return nil
        }
        return path
    }
}

enum ClosetCutoutPath {
    static func expectedOutput(source: String, owner: UUID) throws -> String {
        let prefix = "users/\(owner.uuidString.lowercased())/closet/"
        guard source.hasPrefix(prefix), source.hasSuffix(".jpg") else {
            throw AstraError.validation("That capture is unavailable.")
        }
        let filename = String(source.dropFirst(prefix.count).dropLast(4))
        guard let imageID = UUID(uuidString: filename), filename == imageID.uuidString.lowercased() else {
            throw AstraError.validation("That capture is unavailable.")
        }
        return String(source.dropLast(4)) + "-cutout.png"
    }
}
