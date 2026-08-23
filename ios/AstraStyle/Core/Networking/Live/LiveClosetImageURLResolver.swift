//
//  LiveClosetImageURLResolver.swift
//  AstraStyle
//
//  Signs `user-content` storage paths through Supabase Storage, using the
//  same `createSignedURL(path:expiresIn:)` mechanism
//  `LiveProfileRepository.exportPersonalData()` already uses, and caches
//  the results in memory.
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
        /// Real expiry, not the margin-adjusted one — `isUsable` applies
        /// the margin, so the stored value stays a statement of fact.
        let expiresAt: Date
    }

    private let supabase: SupabaseClient
    private let now: @Sendable () -> Date
    private var cache: [String: CachedSignature] = [:]

    /// - Parameters:
    ///   - supabase: The Storage client.
    ///   - now: Injectable clock. Present so a test can prove the expiry
    ///     and refresh-margin behaviour without sleeping for an hour —
    ///     the numbers above are the entire point of this type, and a
    ///     policy that cannot be tested is a policy that quietly stops
    ///     holding.
    public init(
        supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.supabase = supabase
        self.now = now
    }

    public func resolve(storagePath: String) async throws -> URL {
        if let local = GuestLocalImageStore.fileURL(for: storagePath),
           FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        if let cached = usableCachedURL(for: storagePath) {
            return cached
        }
        do {
            let url = try await supabase.storage
                .from(Self.bucket)
                .createSignedURL(path: storagePath, expiresIn: Self.signedURLLifetime)
            store(url, for: storagePath)
            return url
        } catch {
            throw AstraError.server(String(localized: "Couldn't load that photo.", comment: "Closet image could not be resolved"))
        }
    }

    public func resolve(storagePaths: [String]) async throws -> [String: URL] {
        var resolved: [String: URL] = [:]
        var needsSigning: [String] = []

        for path in storagePaths {
            if let local = GuestLocalImageStore.fileURL(for: path),
               FileManager.default.fileExists(atPath: local.path) {
                resolved[path] = local
            } else if let cached = usableCachedURL(for: path) {
                resolved[path] = cached
            } else {
                needsSigning.append(path)
            }
        }

        // `Set` first: a grid legitimately asks for the same path twice
        // (an item appearing in two sections), and signing it twice would
        // waste half the batch on duplicates.
        for chunk in Array(Set(needsSigning)).chunked(into: Self.batchLimit) {
            for (path, url) in try await sign(chunk) {
                resolved[path] = url
            }
        }
        return resolved
    }

    // MARK: - Signing

    private func sign(_ paths: [String]) async throws -> [String: URL] {
        guard !paths.isEmpty else { return [:] }
        let results: [SignedURLResult]
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

        var signed: [String: URL] = [:]
        for result in results {
            // Keyed by the path Storage echoes back rather than by
            // position: the API returns one object per requested path with
            // that path on it, and trusting the array's ORDER to match the
            // request would be an assumption that fails silently and
            // catastrophically — every tile showing the wrong garment.
            guard let url = result.signedURL else { continue }
            signed[result.path] = url
            store(url, for: result.path)
        }
        return signed
    }

    // MARK: - Cache

    private func usableCachedURL(for path: String) -> URL? {
        guard let cached = cache[path] else { return nil }
        guard cached.expiresAt.timeIntervalSince(now()) > Self.refreshMargin else {
            cache[path] = nil
            return nil
        }
        return cached.url
    }

    private func store(_ url: URL, for path: String) {
        cache[path] = CachedSignature(
            url: url,
            expiresAt: now().addingTimeInterval(TimeInterval(Self.signedURLLifetime))
        )
        pruneExpired()
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

private extension Array {
    /// Splits into fixed-size chunks, last chunk short.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
