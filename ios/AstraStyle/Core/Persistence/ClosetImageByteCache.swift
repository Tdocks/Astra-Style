//
//  ClosetImageByteCache.swift
//  AstraStyle
//
//  Durable, owner-scoped bytes for closet images. The cache is deliberately
//  best-effort: Supabase remains the source of truth and only paths referenced
//  by the signed-in owner's closet can enter it.
//

import Foundation

struct ClosetImageDownload: Sendable {
    let data: Data
    let statusCode: Int?
    let responseURL: URL?
}

func downloadClosetImage(
    from url: URL,
    maxBytes: Int,
    configuration: URLSessionConfiguration = .ephemeral
) async throws -> ClosetImageDownload {
    try await ClosetImageDownloadTask(url: url, maxBytes: maxBytes, configuration: configuration).run()
}

enum ClosetImageDownloadError: Error, Equatable {
    case cancelled
    case invalidResponse
    case exceededByteLimit
}

/// Owns the URLSessionDataTask so invalid or oversized streams are stopped at
/// the transport, rather than merely discarded after retaining their body.
/// Mutable delegate/task state is protected by `lock`; immutable inputs are
/// fixed at initialization. Completion resumes exactly once outside the lock.
final class ClosetImageDownloadTask: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let maxBytes: Int
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ClosetImageDownload, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: URLResponse?
    private var data = Data()
    private var terminalError: Error?
    private var finished = false
    private var cancelled = false

    init(url: URL, maxBytes: Int, configuration: URLSessionConfiguration) {
        self.url = url
        self.maxBytes = maxBytes
        self.configuration = configuration
    }

    func run() async throws -> ClosetImageDownload {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                guard !cancelled else {
                    let error = terminalError ?? ClosetImageDownloadError.cancelled
                    self.continuation = nil
                    lock.unlock()
                    continuation.resume(throwing: error)
                    return
                }
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.dataTask(with: url)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.cancel(with: ClosetImageDownloadError.cancelled)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let responseURL = response.url
        let http = response as? HTTPURLResponse
        guard isAllowedResponseURL(responseURL),
              http.map({ (200 ..< 300).contains($0.statusCode) }) ?? true,
              response.expectedContentLength < 0 || response.expectedContentLength <= Int64(maxBytes) else {
            lock.lock()
            self.response = response
            lock.unlock()
            completionHandler(.cancel)
            cancel(with: ClosetImageDownloadError.invalidResponse)
            return
        }

        lock.lock()
        self.response = response
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(maxBytes, Int(response.expectedContentLength)))
        }
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        guard chunk.count <= maxBytes - data.count else {
            lock.unlock()
            cancel(with: ClosetImageDownloadError.exceededByteLimit)
            return
        }
        data.append(chunk)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        if let terminalError {
            lock.unlock()
            finish(.failure(terminalError))
            return
        }
        let result: Result<ClosetImageDownload, Error>
        if let error {
            result = .failure(error)
        } else {
            let http = response as? HTTPURLResponse
            result = .success(ClosetImageDownload(data: data, statusCode: http?.statusCode, responseURL: response?.url))
        }
        lock.unlock()
        finish(result)
    }

    private func isAllowedResponseURL(_ responseURL: URL?) -> Bool {
        guard let responseURL else { return false }
        return responseURL.scheme?.lowercased() == url.scheme?.lowercased() &&
            responseURL.host()?.lowercased() == url.host()?.lowercased() &&
            responseURL.port == url.port && responseURL.path() == url.path()
    }

    private func cancel(with error: Error) {
        lock.lock()
        cancelled = true
        terminalError = error
        let task = self.task
        lock.unlock()
        task?.cancel()
        finish(.failure(error))
    }

    private func finish(_ result: Result<ClosetImageDownload, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        self.task = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
        continuation?.resume(with: result)
    }
}

struct ClosetImageCacheRevision: Equatable, Sendable {
    let owner: UInt64
    let object: UInt64
}

private struct ClosetImageCacheFile {
    let url: URL
    let size: Int
    let modified: Date
}

private struct ClosetImageDownloadWaiter {
    let id: UUID
    let ownerID: UUID
    let storagePath: String
    let continuation: CheckedContinuation<Bool, Never>
}

/// Disk cache for private closet image bytes. Its identity is (ownerID,
/// canonical storagePath); a signed URL is only a short-lived transport
/// credential and is never used to name a cache entry.
public actor ClosetImageByteCache {
    public static let shared = ClosetImageByteCache()

    private static let defaultMaxCacheBytes = 150 * 1_024 * 1_024
    private static let defaultMaxImageBytes = 20 * 1_024 * 1_024
    private static let defaultMaxConcurrentDownloads = 3
    private static let defaultMaxQueuedDownloads = 24

    private let rootURL: URL
    private let fileManager: FileManager
    private let maxCacheBytes: Int
    private let maxImageBytes: Int
    private let maxConcurrentDownloads: Int
    private let maxQueuedDownloads: Int
    private let downloadImage: @Sendable (URL, Int) async throws -> ClosetImageDownload
    private var inFlight: Set<String> = []
    private var activeDownloads = 0
    private var downloadWaiters: [ClosetImageDownloadWaiter] = []
    private var ownerRevisions: [UUID: UInt64] = [:]
    private var objectRevisions: [String: UInt64] = [:]

    public init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.rootURL = caches.appendingPathComponent("AstraStyle/closet-image-bytes", isDirectory: true)
        self.fileManager = .default
        self.maxCacheBytes = Self.defaultMaxCacheBytes
        self.maxImageBytes = Self.defaultMaxImageBytes
        self.maxConcurrentDownloads = Self.defaultMaxConcurrentDownloads
        self.maxQueuedDownloads = Self.defaultMaxQueuedDownloads
        self.downloadImage = { url, maxBytes in
            try await downloadClosetImage(from: url, maxBytes: maxBytes)
        }
    }

    init(
        rootURL: URL,
        maxCacheBytes: Int,
        maxImageBytes: Int,
        maxConcurrentDownloads: Int = 3,
        maxQueuedDownloads: Int = 24,
        fileManager: FileManager = .default,
        downloadImage: @escaping @Sendable (URL, Int) async throws -> ClosetImageDownload = { url, maxBytes in
            try await downloadClosetImage(from: url, maxBytes: maxBytes)
        }
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.maxCacheBytes = max(0, maxCacheBytes)
        self.maxImageBytes = max(0, maxImageBytes)
        self.maxConcurrentDownloads = max(1, maxConcurrentDownloads)
        self.maxQueuedDownloads = max(0, maxQueuedDownloads)
        self.downloadImage = downloadImage
    }

    /// Returns an existing local file only when the full object path belongs
    /// to the requested owner and matches the app's closet image path forms.
    public func fileURL(ownerID: UUID, storagePath: String) -> URL? {
        guard let destination = destinationURL(ownerID: ownerID, storagePath: storagePath),
              fileManager.fileExists(atPath: destination.path) else { return nil }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
        return destination
    }

    /// Fetches and stores an image without delaying the URL returned to the
    /// view. Failed fetches are intentionally ignored; online rendering can
    /// still use the signed URL, and a later visit can try caching again.
    public func prefetch(signedURL: URL, ownerID: UUID, storagePath: String) async {
        guard let destination = destinationURL(ownerID: ownerID, storagePath: storagePath) else { return }
        let key = destination.path
        guard !Task.isCancelled, !inFlight.contains(key), !fileManager.fileExists(atPath: key) else { return }
        inFlight.insert(key)
        let revision = currentRevision(ownerID: ownerID, storagePath: storagePath)
        defer { inFlight.remove(key) }
        guard await acquireDownloadSlot(ownerID: ownerID, storagePath: storagePath) else { return }
        defer { releaseDownloadSlot() }
        guard !Task.isCancelled,
              currentRevision(ownerID: ownerID, storagePath: storagePath) == revision,
              !fileManager.fileExists(atPath: key) else { return }

        do {
            let download = try await downloadImage(signedURL, maxImageBytes)
            if let statusCode = download.statusCode, !(200..<300).contains(statusCode) { return }
            guard isSameOriginPath(download.responseURL, signedURL),
                  currentRevision(ownerID: ownerID, storagePath: storagePath) == revision else { return }
            guard !download.data.isEmpty, download.data.count <= maxImageBytes else { return }
            try storeDownloadedData(download.data, at: destination)
            evictToLimit()
        } catch {
            // The online image load owns its visible error state. This
            // background copy must never turn a successful render into one.
        }
    }

    /// Removes one cached object after a closet image is deleted or replaced.
    public func remove(ownerID: UUID, storagePath: String) {
        guard Self.isCanonicalOwnedStoragePath(storagePath, ownerID: ownerID) else { return }
        objectRevisions[revisionKey(ownerID: ownerID, storagePath: storagePath), default: 0] &+= 1
        cancelDownloadWaiters(ownerID: ownerID, storagePath: storagePath)
        if let url = destinationURL(ownerID: ownerID, storagePath: storagePath) {
            try? fileManager.removeItem(at: url)
        }
    }

    /// Removes one owner's complete cache after account deletion or explicit
    /// local-data erasure. It cannot target another owner by path input.
    public func removeAll(ownerID: UUID) {
        ownerRevisions[ownerID, default: 0] &+= 1
        cancelDownloadWaiters(ownerID: ownerID)
        try? fileManager.removeItem(at: ownerDirectory(ownerID: ownerID))
    }

    /// Shared tombstone state used to invalidate every resolver instance's
    /// in-memory signed URL for this owner/path after deletion or erasure.
    func invalidationRevision(ownerID: UUID, storagePath: String) -> ClosetImageCacheRevision {
        guard Self.isCanonicalOwnedStoragePath(storagePath, ownerID: ownerID) else {
            return ClosetImageCacheRevision(owner: .max, object: .max)
        }
        return currentRevision(ownerID: ownerID, storagePath: storagePath)
    }

    func pendingDownloadCount() -> Int {
        downloadWaiters.count
    }

    // Internal seam for deterministic storage tests; production network
    // writes go through the size-checked temporary download path above.
    func store(_ data: Data, ownerID: UUID, storagePath: String) throws {
        guard !data.isEmpty, data.count <= maxImageBytes,
              let destination = destinationURL(ownerID: ownerID, storagePath: storagePath) else { return }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: destination, options: .atomic)
            try applyPrivateFileProtection(to: destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        evictToLimit()
    }

    private func storeDownloadedData(_ data: Data, at destination: URL) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporaryDestination = destination.appendingPathExtension("download")
        try? fileManager.removeItem(at: temporaryDestination)
        do {
            try data.write(to: temporaryDestination, options: .atomic)
            try applyPrivateFileProtection(to: temporaryDestination)
            // Replacement is performed only after the complete download has
            // passed size and HTTP checks, so readers never see partial bytes.
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: temporaryDestination, to: destination)
        } catch {
            try? fileManager.removeItem(at: temporaryDestination)
            throw error
        }
    }

    private func acquireDownloadSlot(ownerID: UUID, storagePath: String) async -> Bool {
        guard !Task.isCancelled else { return false }
        guard activeDownloads >= maxConcurrentDownloads else {
            activeDownloads += 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                if activeDownloads < maxConcurrentDownloads {
                    activeDownloads += 1
                    continuation.resume(returning: true)
                } else if downloadWaiters.count >= maxQueuedDownloads {
                    continuation.resume(returning: false)
                } else {
                    downloadWaiters.append(
                        ClosetImageDownloadWaiter(
                            id: id,
                            ownerID: ownerID,
                            storagePath: storagePath,
                            continuation: continuation
                        )
                    )
                }
            }
        } onCancel: {
            Task { await self.cancelDownloadWaiter(id: id) }
        }
    }

    private func releaseDownloadSlot() {
        if downloadWaiters.isEmpty {
            activeDownloads -= 1
        } else {
            downloadWaiters.removeFirst().continuation.resume(returning: true)
        }
    }

    private func cancelDownloadWaiter(id: UUID) {
        guard let index = downloadWaiters.firstIndex(where: { $0.id == id }) else { return }
        downloadWaiters.remove(at: index).continuation.resume(returning: false)
    }

    private func cancelDownloadWaiters(ownerID: UUID, storagePath: String? = nil) {
        var retained: [ClosetImageDownloadWaiter] = []
        for waiter in downloadWaiters {
            let matchesOwner = waiter.ownerID == ownerID
            let matchesPath = storagePath == nil || waiter.storagePath == storagePath
            if matchesOwner && matchesPath {
                waiter.continuation.resume(returning: false)
            } else {
                retained.append(waiter)
            }
        }
        downloadWaiters = retained
    }

    private func destinationURL(ownerID: UUID, storagePath: String) -> URL? {
        guard Self.isOwnedClosetImagePath(storagePath, ownerID: ownerID) else { return nil }
        let prefix = "users/\(ownerID.uuidString.lowercased())/closet/"
        let relative = String(storagePath.dropFirst(prefix.count))
        return ownerDirectory(ownerID: ownerID).appendingPathComponent(relative, isDirectory: false)
    }

    private func ownerDirectory(ownerID: UUID) -> URL {
        rootURL.appendingPathComponent(ownerID.uuidString.lowercased(), isDirectory: true)
    }

    private func currentRevision(ownerID: UUID, storagePath: String) -> ClosetImageCacheRevision {
        let prefix = ownerRevisions[ownerID, default: 0]
        let object = objectRevisions[revisionKey(ownerID: ownerID, storagePath: storagePath), default: 0]
        return ClosetImageCacheRevision(owner: prefix, object: object)
    }

    private func revisionKey(ownerID: UUID, storagePath: String) -> String {
        "\(ownerID.uuidString.lowercased())|\(storagePath)"
    }

    private func isSameOriginPath(_ responseURL: URL?, _ requestedURL: URL) -> Bool {
        guard let responseURL,
              responseURL.scheme?.lowercased() == requestedURL.scheme?.lowercased(),
              responseURL.host()?.lowercased() == requestedURL.host()?.lowercased(),
              responseURL.port == requestedURL.port,
              responseURL.path() == requestedURL.path() else { return false }
        return true
    }

    /// Supports current flat UUID images, deterministic -cutout.png files,
    /// and the documented legacy item/image UUID layout. No arbitrary folder,
    /// traversal component, foreign owner, query, or alternate bucket enters.
    nonisolated static func isOwnedClosetImagePath(_ path: String, ownerID: UUID) -> Bool {
        let prefix = "users/\(ownerID.uuidString.lowercased())/closet/"
        guard path == path.lowercased(), path.hasPrefix(prefix) else { return false }
        let parts = path.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return false }
        if parts.count == 1 {
            let filename = String(parts[0])
            if filename.hasSuffix("-cutout.png") {
                return UUID(uuidString: String(filename.dropLast("-cutout.png".count))) != nil
            }
            return isImageFilename(filename)
        }
        guard parts.count == 2, let itemID = UUID(uuidString: String(parts[0])),
              String(parts[0]) == itemID.uuidString.lowercased() else { return false }
        return isImageFilename(String(parts[1]))
    }

    nonisolated static func isCanonicalOwnedStoragePath(_ path: String, ownerID: UUID) -> Bool {
        let prefix = "users/\(ownerID.uuidString.lowercased())/"
        guard path == path.lowercased(), path.hasPrefix(prefix) else { return false }
        let components = path.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return false }
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".." &&
                component.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
        }
    }

    private static func isImageFilename(_ filename: String) -> Bool {
        guard let dot = filename.lastIndex(of: ".") else { return false }
        var stem = String(filename[..<dot])
        let ext = String(filename[filename.index(after: dot)...])
        if stem.hasSuffix(".thumb") {
            stem = String(stem.dropLast(".thumb".count))
        }
        if stem.hasSuffix("-cutout") {
            stem = String(stem.dropLast("-cutout".count))
        }
        return UUID(uuidString: stem) != nil && stem == stem.lowercased() && ["jpg", "png"].contains(ext)
    }

    private func applyPrivateFileProtection(to url: URL) throws {
        try fileManager.setAttributes([
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
            .posixPermissions: 0o600
        ], ofItemAtPath: url.path)
    }

    private func evictToLimit() {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var files: [ClosetImageCacheFile] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  !url.lastPathComponent.hasSuffix(".download") else { continue }
            files.append(ClosetImageCacheFile(url: url, size: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast))
        }
        var total = files.reduce(0) { $0 + $1.size }
        for file in files.sorted(by: { $0.modified < $1.modified }) where total > maxCacheBytes {
            try? fileManager.removeItem(at: file.url)
            total -= file.size
        }
    }
}
