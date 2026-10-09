//
//  LiveClosetImageURLResolver.swift
//  AstraStyle
//
//  Signs the current user's `user-content` paths through Supabase Storage and
//  signs selected public-look images through the authenticated lookbook Edge
//  Function. Owner signatures are cached in memory; peer signatures are short
//  lived and never expose a storage path to the app.
//
//  THE THREE NUMBERS, AND WHY THEY ARE THOSE NUMBERS.
//
//  * `signedURLLifetime = 3600` (one hour). The upper bound is what a
//    leaked URL is worth: a signed URL is a bearer token for one private
//    photograph, and it works for anyone who has it until it expires. The
//    lower bound is round trips — closet browsing is bursty (open the tab,
//    scroll, open an item, go back), and anything under a few minutes
//    would re-sign the same tiles repeatedly within a single sitting. An
//    hour comfortably covers a session while guaranteeing that a URL
//    captured in a screenshot, a log or a shared debug bundle is dead the
//    same morning.
//
//  * `refreshMargin = 300` (five minutes). A cached URL is treated as
//    expired five minutes early. Without a margin, a tile that starts
//    loading one second before expiry gets handed a URL that dies
//    mid-transfer, and the user sees the no-photo fallback on a photo that
//    exists. Five minutes is far longer than any image transfer and costs
//    nothing but signing slightly sooner.
//
//  * `batchLimit = 100` paths per request. Storage's batch sign endpoint
//    takes an array; chunking bounds the request body and stops one
//    enormous closet from turning a batch call back into a timeout. A
//    250-item closet is three requests instead of 250.
//
//  NOT `@MainActor`. This is an `actor` — the cache is genuinely shared
//  mutable state reached from every closet surface at once, and an actor
//  is what makes concurrent grid tiles safe without pinning network I/O to
//  the main thread.
//

import Foundation
import Supabase

public actor LiveClosetImageURLResolver: ClosetImageURLResolving {
    /// Seconds a signed URL is valid for. See this file's header.
    static let signedURLLifetime = 3600

    /// How long before real expiry a cached URL stops being handed out.
    static let refreshMargin: TimeInterval = 300

    /// Maximum paths per batch sign request.
    static let batchLimit = 100
    /// The one private bucket (spec §15). Not "closet" — `closet` is a
    /// folder inside this bucket. Same fact that
    /// `LiveClosetRepository.uploadCaptured()` documents at its own call
    /// site; getting it wrong there failed the upload outright, and getting
    /// it wrong here would fail every read.
    private static let bucket = "user-content"

    private struct CachedSignature {
        let url: URL
        let ownerID: UUID
        let revision: ClosetImageCacheRevision
        /// Real expiry, not the margin-adjusted one — `isUsable` applies
        /// the margin, so the stored value stays a statement of fact.
        let expiresAt: Date
    }

    private let supabase: SupabaseClient
    private let apiClient: AstraAPIClient
    private let now: @Sendable () -> Date
    private let currentUserID: @Sendable () async -> UUID?
    private var cache: [String: CachedSignature] = [:]

    /// - Parameters:
    ///   - supabase: The Storage client.
    ///   - now: Injectable clock. Present so a test can prove the expiry
    ///     and refresh-margin behaviour without sleeping for an hour —
    ///     the numbers above are the entire point of this type, and a
    ///     policy that cannot be tested is a policy that quietly stops
    ///     holding.
    public init(
        apiClient: AstraAPIClient,
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current),
        now: @escaping @Sendable () -> Date = { Date() },
        currentUserID: (@Sendable () async -> UUID?)? = nil
    ) {
        self.supabase = supabase
        self.apiClient = apiClient
        self.now = now
        self.currentUserID = currentUserID ?? {
            if let id = supabase.auth.currentSession?.user.id { return id }
            return try? await supabase.auth.session.user.id
        }
    }

    public func resolve(storagePath: String) async throws -> URL {
        let ownerID = try await authenticatedOwnerID()
        guard Self.isAccessiblePrivatePath(storagePath, ownerID: ownerID) else {
            throw AstraError.auth("That photo belongs to a different account or is unavailable.")
        }
        if let local = GuestLocalImageStore.fileURL(for: storagePath),
           FileManager.default.fileExists(atPath: local.path) {
            try await verifyOwner(ownerID)
            return local
        }
        let cachedFile = await ClosetImageByteCache.shared.fileURL(ownerID: ownerID, storagePath: storagePath)
        try await verifyOwner(ownerID)
        if let local = cachedFile {
            return local
        }
        if let cached = await usableCachedSignature(for: storagePath, ownerID: ownerID) {
            try await verifyOwner(ownerID)
            guard await signatureRevisionIsCurrent(cached, path: storagePath) else {
                cache[storagePath] = nil
                return try await signOne(storagePath, ownerID: ownerID)
            }
            prefetch(cached.url, storagePath: storagePath, ownerID: ownerID)
            return cached.url
        }
        return try await signOne(storagePath, ownerID: ownerID)
    }

    private func signOne(_ storagePath: String, ownerID: UUID) async throws -> URL {
        let revisions = await ClosetImageByteCache.shared.invalidationRevision(ownerID: ownerID, storagePath: storagePath)
        let url: URL
        do {
            url = try await supabase.storage
                .from(Self.bucket)
                .createSignedURL(path: storagePath, expiresIn: Self.signedURLLifetime)
        } catch {
            throw AstraError.server(String(localized: "Couldn't load that photo.", comment: "Closet image could not be resolved"))
        }
        try await verifyOwner(ownerID)
        let latestRevision = await ClosetImageByteCache.shared.invalidationRevision(ownerID: ownerID, storagePath: storagePath)
        guard latestRevision == revisions else {
            throw AstraError.server(String(localized: "That photo changed while it was loading. Try again.", comment: "Closet image invalidated during signing"))
        }
        store(url, for: storagePath, ownerID: ownerID, revision: latestRevision)
        prefetch(url, storagePath: storagePath, ownerID: ownerID)
        return url
    }

    public func resolve(storagePaths: [String]) async throws -> [String: URL] {
        guard !storagePaths.isEmpty else { return [:] }
        let ownerID = try await authenticatedOwnerID()
        var resolved: [String: URL] = [:]
        var needsSigning: [String] = []

        for path in storagePaths {
            guard Self.isAccessiblePrivatePath(path, ownerID: ownerID) else { continue }
            if let local = GuestLocalImageStore.fileURL(for: path),
               FileManager.default.fileExists(atPath: local.path) {
                resolved[path] = local
            } else {
                let cachedFile = await ClosetImageByteCache.shared.fileURL(ownerID: ownerID, storagePath: path)
                try await verifyOwner(ownerID)
                if let local = cachedFile {
                    resolved[path] = local
                } else if let cached = await usableCachedSignature(for: path, ownerID: ownerID) {
                    try await verifyOwner(ownerID)
                    if await signatureRevisionIsCurrent(cached, path: path) {
                        resolved[path] = cached.url
                        prefetch(cached.url, storagePath: path, ownerID: ownerID)
                    } else {
                        cache[path] = nil
                        needsSigning.append(path)
                    }
                } else {
                    needsSigning.append(path)
                }
            }
        }

        // `Set` first: a grid legitimately asks for the same path twice
        // (an item appearing in two sections), and signing it twice would
        // waste half the batch on duplicates.
        for chunk in Array(Set(needsSigning)).chunked(into: Self.batchLimit) {
            for (path, url) in try await sign(chunk, ownerID: ownerID) {
                resolved[path] = url
            }
        }
        try await verifyOwner(ownerID)
        return resolved
    }

    public func resolve(publicLookImages: [PublicLookImageReference]) async throws -> [UUID: URL] {
        guard !publicLookImages.isEmpty else { return [:] }
        let unique = Array(Set(publicLookImages))
        var resolved: [UUID: URL] = [:]
        for start in stride(from: 0, to: unique.count, by: Self.batchLimit) {
            let batch = Array(unique[start ..< min(start + Self.batchLimit, unique.count)])
            do {
                let response = try await apiClient.send(
                    .signPublicLookImages,
                    body: PublicLookImageSigningRequest(images: batch),
                    as: PublicLookImageSigningResponse.self
                )
                for image in response.images {
                    resolved[image.imageID] = image.signedURL
                }
            } catch {
                throw AstraError.server(String(localized: "Couldn't load photos for that shared look.", comment: "Public look image signing failed"))
            }
        }
        return resolved
    }

    // MARK: - Signing

    private func sign(_ paths: [String], ownerID: UUID) async throws -> [String: URL] {
        guard !paths.isEmpty else { return [:] }
        let results: [SignedURLResult]
        let revisionsBefore = await invalidationRevisions(ownerID: ownerID, paths: paths)
        do {
            results = try await supabase.storage
                .from(Self.bucket)
                .createSignedURLs(paths: paths, expiresIn: Self.signedURLLifetime)
        } catch {
            // The REQUEST failed (offline, 401, bucket missing). Individual
            // unsignable paths do not land here — Storage reports those as
            // per-item failures inside a successful response, which is why
            // the loop below can drop them silently while this throws.
            throw AstraError.network(String(localized: "Couldn't load your closet photos. Check your connection and try again.", comment: "Batch closet image resolution failed"))
        }
        try await verifyOwner(ownerID)
        let revisionsAfter = await invalidationRevisions(ownerID: ownerID, paths: paths)

        var signed: [String: URL] = [:]
        for result in results {
            guard Self.isAccessiblePrivatePath(result.path, ownerID: ownerID) else { continue }
            // Keyed by the path Storage echoes back rather than by
            // position: the API returns one object per requested path with
            // that path on it, and trusting the array's ORDER to match the
            // request would be an assumption that fails silently and
            // catastrophically — every tile showing the wrong garment.
            guard let url = result.signedURL else { continue }
            guard revisionsBefore[result.path] == revisionsAfter[result.path],
                  let revision = revisionsAfter[result.path] else { continue }
            signed[result.path] = url
            store(url, for: result.path, ownerID: ownerID, revision: revision)
            prefetch(url, storagePath: result.path, ownerID: ownerID)
        }
        return signed
    }

    private func authenticatedOwnerID() async throws -> UUID {
        guard let ownerID = await currentUserID() else {
            throw AstraError.auth("Sign in to view your closet photos.")
        }
        return ownerID
    }

    private func verifyOwner(_ expectedOwnerID: UUID) async throws {
        guard await currentUserID() == expectedOwnerID else {
            throw AstraError.auth("Your account changed while loading that photo. Try again.")
        }
    }

    private static func isAccessiblePrivatePath(_ path: String, ownerID: UUID) -> Bool {
        if GuestLocalImageStore.fileURL(for: path) != nil {
            let prefix = "\(GuestLocalImageStore.pathPrefix)\(ownerID.uuidString.lowercased())/"
            return path.hasPrefix(prefix)
        }
        let prefix = "users/\(ownerID.uuidString.lowercased())/"
        guard path == path.lowercased(), path.hasPrefix(prefix) else { return false }
        let components = path.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return false }
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".." &&
                component.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
        }
    }

    /// Account deletion and image removal callers can invalidate durable
    /// bytes without having to know the cache's on-disk layout.
    public func removeCachedImage(ownerID: UUID, storagePath: String) async {
        cache[storagePath] = nil
        await ClosetImageByteCache.shared.remove(ownerID: ownerID, storagePath: storagePath)
    }

    public func removeAllCachedImages(ownerID: UUID) async {
        let prefix = "users/\(ownerID.uuidString.lowercased())/"
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
        await ClosetImageByteCache.shared.removeAll(ownerID: ownerID)
    }

    private func prefetch(_ url: URL, storagePath: String, ownerID: UUID?) {
        guard let ownerID,
              ClosetImageByteCache.isOwnedClosetImagePath(storagePath, ownerID: ownerID) else { return }
        Task {
            await ClosetImageByteCache.shared.prefetch(
                signedURL: url,
                ownerID: ownerID,
                storagePath: storagePath
            )
        }
    }

    // MARK: - Cache

    func usableCachedURL(for path: String, ownerID: UUID) async -> URL? {
        await usableCachedSignature(for: path, ownerID: ownerID)?.url
    }

    private func usableCachedSignature(for path: String, ownerID: UUID) async -> CachedSignature? {
        guard let cached = cache[path], cached.ownerID == ownerID else { return nil }
        guard cached.expiresAt.timeIntervalSince(now()) > Self.refreshMargin else {
            cache[path] = nil
            return nil
        }
        let revision = await ClosetImageByteCache.shared.invalidationRevision(ownerID: ownerID, storagePath: path)
        guard let latest = cache[path],
              latest.ownerID == ownerID,
              latest.url == cached.url,
              latest.revision == cached.revision else { return nil }
        guard revision == cached.revision else {
            cache[path] = nil
            return nil
        }
        return cached
    }

    private func signatureRevisionIsCurrent(_ signature: CachedSignature, path: String) async -> Bool {
        let revision = await ClosetImageByteCache.shared.invalidationRevision(
            ownerID: signature.ownerID,
            storagePath: path
        )
        return revision == signature.revision &&
            cache[path]?.url == signature.url &&
            cache[path]?.revision == signature.revision &&
            cache[path]?.ownerID == signature.ownerID
    }

    func store(_ url: URL, for path: String, ownerID: UUID, revision: ClosetImageCacheRevision) {
        cache[path] = CachedSignature(
            url: url,
            ownerID: ownerID,
            revision: revision,
            expiresAt: now().addingTimeInterval(TimeInterval(Self.signedURLLifetime))
        )
        pruneExpired()
    }

    private func invalidationRevisions(ownerID: UUID, paths: [String]) async -> [String: ClosetImageCacheRevision] {
        var revisions: [String: ClosetImageCacheRevision] = [:]
        for path in paths {
            revisions[path] = await ClosetImageByteCache.shared.invalidationRevision(ownerID: ownerID, storagePath: path)
        }
        return revisions
    }

    /// Drops entries that can no longer be handed out.
    ///
    /// This is the only eviction: there is no size cap, because the cache
    /// is bounded by the number of images in one user's closet (hundreds,
    /// at a few hundred bytes of URL each) and every entry becomes
    /// collectable within the hour. A count limit would add a policy — and
    /// a wrong-eviction bug — to solve a problem this cache cannot have.
    private func pruneExpired() {
        let cutoff = now()
        cache = cache.filter { $0.value.expiresAt > cutoff }
    }
}

private struct PublicLookImageSigningRequest: Encodable, Sendable {
    let images: [PublicLookImageReference]
}

private struct PublicLookImageSigningResponse: Decodable, Sendable {
    struct Image: Decodable, Sendable {
        let imageID: UUID
        let signedURL: URL

        enum CodingKeys: String, CodingKey {
            case imageID = "image_id"
            case signedURL = "signed_url"
        }
    }

    let images: [Image]
}

private extension Array {
    /// Splits into fixed-size chunks, last chunk short.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
