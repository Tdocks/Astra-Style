import Foundation
import XCTest
@testable import AstraStyle

final class ClosetImageByteCacheTests: XCTestCase {
    func testOversizedStreamCancelsItsURLSessionTask() async throws {
        let stopped = expectation(description: "oversized URLProtocol request is stopped")
        OversizedImageURLProtocol.stopObserver.setHandler { stopped.fulfill() }
        defer { OversizedImageURLProtocol.stopObserver.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OversizedImageURLProtocol.self]
        configuration.timeoutIntervalForRequest = 3
        let url = try XCTUnwrap(URL(string: "https://oversized.example.test/image.png"))

        do {
            _ = try await downloadClosetImage(from: url, maxBytes: 4, configuration: configuration)
            XCTFail("Oversized image response should fail")
        } catch let error as ClosetImageDownloadError {
            XCTAssertEqual(error, .exceededByteLimit)
        } catch {
            XCTFail("Expected byte-limit cancellation, received \(error)")
        }
        await fulfillment(of: [stopped], timeout: 2)
    }

    func testStoredBytesAreScopedToOwnerAndCanonicalPath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ClosetImageByteCache(rootURL: root, maxCacheBytes: 1_024, maxImageBytes: 1_024)
        let owner = UUID()
        let peer = UUID()
        let imageID = UUID().uuidString.lowercased()
        let path = "users/\(owner.uuidString.lowercased())/closet/\(imageID).png"
        let bytes = Data([1, 2, 3, 4])

        try await cache.store(bytes, ownerID: owner, storagePath: path)

        let local = await cache.fileURL(ownerID: owner, storagePath: path)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(local)), bytes)
        let peerLookup = await cache.fileURL(ownerID: peer, storagePath: path)
        let foreignPathLookup = await cache.fileURL(ownerID: owner, storagePath: "users/\(peer.uuidString.lowercased())/closet/\(imageID).png")
        XCTAssertNil(peerLookup)
        XCTAssertNil(foreignPathLookup)
    }

    func testAcceptsCurrentCutoutAndLegacyNestedImagePathsOnly() {
        let owner = UUID()
        let ownerPrefix = "users/\(owner.uuidString.lowercased())/closet/"
        let item = UUID().uuidString.lowercased()
        let image = UUID().uuidString.lowercased()

        XCTAssertTrue(ClosetImageByteCache.isOwnedClosetImagePath(ownerPrefix + image + ".jpg", ownerID: owner))
        XCTAssertTrue(ClosetImageByteCache.isOwnedClosetImagePath(ownerPrefix + image + "-cutout.png", ownerID: owner))
        XCTAssertTrue(ClosetImageByteCache.isOwnedClosetImagePath(ownerPrefix + item + "/" + image + ".png", ownerID: owner))
        XCTAssertFalse(ClosetImageByteCache.isOwnedClosetImagePath(ownerPrefix + "../" + image + ".png", ownerID: owner))
        XCTAssertFalse(ClosetImageByteCache.isOwnedClosetImagePath(ownerPrefix + "nested/other/" + image + ".png", ownerID: owner))
        XCTAssertFalse(ClosetImageByteCache.isOwnedClosetImagePath(ownerPrefix + image + ".gif", ownerID: owner))
        XCTAssertFalse(ClosetImageByteCache.isOwnedClosetImagePath("users/\(UUID().uuidString.lowercased())/closet/\(image).png", ownerID: owner))
    }

    func testCacheEnforcesPerImageLimitAndOwnerRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ClosetImageByteCache(rootURL: root, maxCacheBytes: 1_024, maxImageBytes: 3)
        let owner = UUID()
        let peer = UUID()
        let image = UUID().uuidString.lowercased()
        let path = "users/\(owner.uuidString.lowercased())/closet/\(image).png"

        try await cache.store(Data([1, 2, 3]), ownerID: owner, storagePath: path)
        try await cache.store(Data([1, 2, 3, 4]), ownerID: owner, storagePath: "users/\(owner.uuidString.lowercased())/closet/\(UUID().uuidString.lowercased()).png")
        let beforeRemoval = await cache.fileURL(ownerID: owner, storagePath: path)
        XCTAssertNotNil(beforeRemoval)

        await cache.removeAll(ownerID: owner)
        let afterRemoval = await cache.fileURL(ownerID: owner, storagePath: path)
        XCTAssertNil(afterRemoval)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(peer.uuidString.lowercased()).path))
    }

    func testCacheEvictsFilesToRespectTotalByteLimit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ClosetImageByteCache(rootURL: root, maxCacheBytes: 5, maxImageBytes: 4)
        let owner = UUID()
        let prefix = "users/\(owner.uuidString.lowercased())/closet/"

        try await cache.store(Data([1, 2, 3]), ownerID: owner, storagePath: prefix + "\(UUID().uuidString.lowercased()).png")
        try await cache.store(Data([4, 5, 6]), ownerID: owner, storagePath: prefix + "\(UUID().uuidString.lowercased()).png")

        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey])
        let files = (enumerator?.allObjects.compactMap { $0 as? URL } ?? []).filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        let totalBytes = try files.reduce(0) { total, url in
            total + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        XCTAssertLessThanOrEqual(totalBytes, 5)
        XCTAssertEqual(files.count, 1)
    }

    func testRemovalDuringDownloadPreventsBytesFromBeingRecreated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let barrier = DownloadBarrier()
        let cache = ClosetImageByteCache(
            rootURL: root,
            maxCacheBytes: 1_024,
            maxImageBytes: 1_024,
            downloadImage: { requestedURL, _ in
                await barrier.pause()
                return ClosetImageDownload(data: Data([9, 8, 7]), statusCode: 200, responseURL: requestedURL)
            }
        )
        let owner = UUID()
        let image = UUID().uuidString.lowercased()
        let path = "users/\(owner.uuidString.lowercased())/closet/\(image).png"
        let signedURL = try XCTUnwrap(URL(string: "https://storage.example.test/storage/v1/object/sign/\(path)?token=temporary"))

        let pending = Task {
            await cache.prefetch(signedURL: signedURL, ownerID: owner, storagePath: path)
        }
        await barrier.waitUntilStarted()
        await cache.remove(ownerID: owner, storagePath: path)
        await barrier.resume()
        await pending.value

        let result = await cache.fileURL(ownerID: owner, storagePath: path)
        XCTAssertNil(result)
    }

    func testPrefetchConcurrencyRemainsBoundedAcrossLargeBatches() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = DownloadConcurrencyProbe()
        let cache = ClosetImageByteCache(
            rootURL: root,
            maxCacheBytes: 10_000,
            maxImageBytes: 1_024,
            maxConcurrentDownloads: 2,
            downloadImage: { requestedURL, _ in
                await probe.beginAndWait()
                return ClosetImageDownload(data: Data([1, 2, 3]), statusCode: 200, responseURL: requestedURL)
            }
        )
        let owner = UUID()
        let paths = (0 ..< 8).map { _ in
            "users/\(owner.uuidString.lowercased())/closet/\(UUID().uuidString.lowercased()).png"
        }
        let signedURLs = try paths.map {
            try XCTUnwrap(URL(string: "https://storage.example.test/storage/v1/object/sign/\($0)?token=temporary"))
        }

        let tasks = zip(paths, signedURLs).map { pair in
            let (path, url) = pair
            return Task {
                await cache.prefetch(signedURL: url, ownerID: owner, storagePath: path)
            }
        }
        await probe.waitUntilStarted(count: 2)
        let activeAtLimit = await probe.maximumActive
        XCTAssertEqual(activeAtLimit, 2)
        await probe.releaseAll()
        for task in tasks {
            await task.value
        }
        let observedMaximum = await probe.maximumActive
        XCTAssertEqual(observedMaximum, 2)
    }

    func testOwnerRemovalCancelsQueuedPrefetchAndInvalidatesActiveDownload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = DownloadConcurrencyProbe()
        let cache = ClosetImageByteCache(
            rootURL: root,
            maxCacheBytes: 1_024,
            maxImageBytes: 1_024,
            maxConcurrentDownloads: 1,
            downloadImage: { requestedURL, _ in
                await probe.beginAndWait()
                return ClosetImageDownload(data: Data([1, 2, 3]), statusCode: 200, responseURL: requestedURL)
            }
        )
        let owner = UUID()
        let paths = (0 ..< 2).map { _ in
            "users/\(owner.uuidString.lowercased())/closet/\(UUID().uuidString.lowercased()).png"
        }
        let urls = try paths.map {
            try XCTUnwrap(URL(string: "https://storage.example.test/storage/v1/object/sign/\($0)?token=temporary"))
        }

        let activeTask = Task {
            await cache.prefetch(signedURL: urls[0], ownerID: owner, storagePath: paths[0])
        }
        await probe.waitUntilStarted(count: 1)
        let queuedTask = Task {
            await cache.prefetch(signedURL: urls[1], ownerID: owner, storagePath: paths[1])
        }
        while await cache.pendingDownloadCount() == 0 {
            await Task.yield()
        }

        await cache.removeAll(ownerID: owner)
        await queuedTask.value
        let startedAfterRemoval = await probe.startedDownloads
        XCTAssertEqual(startedAfterRemoval, 1)
        await probe.releaseAll()
        await activeTask.value

        let activeResult = await cache.fileURL(ownerID: owner, storagePath: paths[0])
        let queuedResult = await cache.fileURL(ownerID: owner, storagePath: paths[1])
        XCTAssertNil(activeResult)
        XCTAssertNil(queuedResult)
    }

    func testPrefetchQueueHasABoundedSize() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = DownloadConcurrencyProbe()
        let cache = ClosetImageByteCache(
            rootURL: root,
            maxCacheBytes: 1_024,
            maxImageBytes: 1_024,
            maxConcurrentDownloads: 1,
            maxQueuedDownloads: 2,
            downloadImage: { requestedURL, _ in
                await probe.beginAndWait()
                return ClosetImageDownload(data: Data([1]), statusCode: 200, responseURL: requestedURL)
            }
        )
        let owner = UUID()
        let entries = try (0 ..< 8).map { _ in
            let path = "users/\(owner.uuidString.lowercased())/closet/\(UUID().uuidString.lowercased()).png"
            let url = try XCTUnwrap(URL(string: "https://storage.example.test/storage/v1/object/sign/\(path)?token=temporary"))
            return (path, url)
        }

        let tasks = entries.map { entry in
            Task { await cache.prefetch(signedURL: entry.1, ownerID: owner, storagePath: entry.0) }
        }
        await probe.waitUntilStarted(count: 1)
        while await cache.pendingDownloadCount() < 2 { await Task.yield() }
        let queued = await cache.pendingDownloadCount()
        XCTAssertEqual(queued, 2)
        let started = await probe.startedDownloads
        XCTAssertEqual(started, 1)

        await cache.removeAll(ownerID: owner)
        await probe.releaseAll()
        for task in tasks {
            await task.value
        }
        let startedAfterRemoval = await probe.startedDownloads
        XCTAssertEqual(startedAfterRemoval, 1)
    }
}

private final class OversizedImageURLProtocol: URLProtocol {
    static let stopObserver = URLProtocolStopObserver()

    // URLProtocol's class methods must be overridden as class methods.
    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "image/png"]
        ) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 1, count: 8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        Self.stopObserver.notify()
    }
}

private final class URLProtocolStopObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    func setHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func notify() {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?()
    }
}

private actor DownloadBarrier {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var resumeWaiter: CheckedContinuation<Void, Never>?

    func pause() async {
        started = true
        startWaiter?.resume()
        await withCheckedContinuation { resumeWaiter = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func resume() {
        resumeWaiter?.resume()
        resumeWaiter = nil
    }
}

private actor DownloadConcurrencyProbe {
    private var active = 0
    private(set) var maximumActive = 0
    private(set) var startedDownloads = 0
    private var startWaiter: (target: Int, continuation: CheckedContinuation<Void, Never>)?
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func beginAndWait() async {
        active += 1
        startedDownloads += 1
        maximumActive = max(maximumActive, active)
        if let startWaiter, startedDownloads >= startWaiter.target {
            self.startWaiter = nil
            startWaiter.continuation.resume()
        }
        if !isReleased {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        active -= 1
    }

    func waitUntilStarted(count: Int) async {
        guard startedDownloads < count else { return }
        await withCheckedContinuation { startWaiter = (count, $0) }
    }

    func releaseAll() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
