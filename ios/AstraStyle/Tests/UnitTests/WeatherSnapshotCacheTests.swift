import CoreLocation
import Foundation
import Testing
@testable import AstraStyle

@Suite("Owner-scoped last-known weather")
struct WeatherSnapshotCacheTests {
    @Test("Provider failure uses only this owner's same-region reading")
    func providerFailureUsesOwnedSameRegionSnapshot() async throws {
        let ownerID = UUID()
        let owner = WeatherTestCurrentOwner(ownerID)
        let cache = WeatherTestCache()
        let resolver = WeatherSnapshotFallbackResolver(
            cache: cache,
            currentUserID: { await owner.value }
        )
        let region = WeatherRegionKey(latitude: 40.7128, longitude: -74.0060)
        let now = Date.now
        let snapshot = Self.snapshot(observedAt: now.addingTimeInterval(-30 * 60))
        try await cache.store(snapshot, ownerID: ownerID, region: region)

        let reading = try await resolver.reading(
            ownerID: ownerID,
            region: region,
            now: now,
            fetch: { throw AstraError.provider("offline") }
        )

        #expect(reading.snapshot == snapshot)
        #expect(reading.source == .lastKnown)
        #expect(reading.snapshot.observedAt == snapshot.observedAt)
    }

    @Test("Other owner and changed coarse region never reuse a reading")
    func ownerAndRegionArePartOfCacheIdentity() async throws {
        let ownerID = UUID()
        let cache = WeatherTestCache()
        let region = WeatherRegionKey(latitude: 40.7128, longitude: -74.0060)
        try await cache.store(Self.snapshot(observedAt: .now), ownerID: ownerID, region: region)

        #expect(await cache.load(ownerID: UUID(), region: region, now: .now) == nil)
        #expect(await cache.load(
            ownerID: ownerID,
            region: WeatherRegionKey(latitude: 41.0, longitude: -74.0),
            now: .now
        ) == nil)
    }

    @Test("Expired and implausibly future observations are rejected")
    func freshnessBounds() async throws {
        let ownerID = UUID()
        let cache = WeatherTestCache()
        let region = WeatherRegionKey(latitude: 40.7, longitude: -74.0)
        let now = Date.now
        try await cache.store(
            Self.snapshot(observedAt: now.addingTimeInterval(-2 * 60 * 60 - 1)),
            ownerID: ownerID,
            region: region
        )
        #expect(await cache.load(ownerID: ownerID, region: region, now: now) == nil)

        try await cache.store(
            Self.snapshot(observedAt: now.addingTimeInterval(6 * 60)),
            ownerID: ownerID,
            region: region
        )
        #expect(await cache.load(ownerID: ownerID, region: region, now: now) == nil)
    }

    @Test("Account switch during provider suspension prevents fallback")
    func accountSwitchDuringFetchFailsClosed() async throws {
        let ownerID = UUID()
        let peerID = UUID()
        let owner = WeatherTestCurrentOwner(ownerID)
        let cache = WeatherTestCache()
        let resolver = WeatherSnapshotFallbackResolver(
            cache: cache,
            currentUserID: { await owner.value }
        )
        let region = WeatherRegionKey(latitude: 40.7, longitude: -74.0)
        try await cache.store(Self.snapshot(observedAt: .now), ownerID: ownerID, region: region)

        do {
            _ = try await resolver.reading(
                ownerID: ownerID,
                region: region,
                fetch: {
                    await owner.set(peerID)
                    throw AstraError.provider("offline")
                }
            )
            Issue.record("An account switch must not return the previous owner's forecast.")
        } catch let error as AstraError {
            #expect(error.category == .auth)
        }
    }

    @Test("No provider timestamp means no cache entry")
    func missingObservationTimeIsNotPersisted() async throws {
        let ownerID = UUID()
        let cache = WeatherTestCache()
        let region = WeatherRegionKey(latitude: 40.7, longitude: -74.0)
        try await cache.store(Self.snapshot(observedAt: nil), ownerID: ownerID, region: region)
        #expect(await cache.load(ownerID: ownerID, region: region, now: .now) == nil)
    }

    @Test("Protected disk cache survives service recreation and removes only its owner")
    func diskCacheSurvivesRecreationAndOwnerRemoval() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("weather-cache-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let ownerID = UUID()
        let peerID = UUID()
        let region = WeatherRegionKey(latitude: 40.7128, longitude: -74.0060)
        // The shared `JSONEncoder.astraDefault` ISO-8601 strategy stores whole
        // seconds. Keep the fixture aligned to that precision so full-value
        // equality verifies every field without depending on lost fractions.
        let observationTime = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down) - 20 * 60)
        let snapshot = Self.snapshot(observedAt: observationTime)
        let firstCache = FileWeatherSnapshotCache(directoryURL: folder)
        try await firstCache.store(snapshot, ownerID: ownerID, region: region)
        try await firstCache.store(snapshot, ownerID: peerID, region: region)
        let backupValues = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(backupValues.isExcludedFromBackup == true)
        let cachedFile = folder.appendingPathComponent("weather-\(ownerID.uuidString.lowercased()).json")
        let fileBackupValues = try cachedFile.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(fileBackupValues.isExcludedFromBackup == true)

        let reopenedCache = FileWeatherSnapshotCache(directoryURL: folder)
        #expect(await reopenedCache.load(ownerID: ownerID, region: region, now: .now) == snapshot)
        try await reopenedCache.remove(ownerID: ownerID)
        #expect(await reopenedCache.load(ownerID: ownerID, region: region, now: .now) == nil)
        #expect(await reopenedCache.load(ownerID: peerID, region: region, now: .now) == snapshot)
    }

    @Test("Cancellation does not turn into a stale-weather success")
    func cancellationDoesNotUseFallback() async throws {
        let ownerID = UUID()
        let owner = WeatherTestCurrentOwner(ownerID)
        let cache = WeatherTestCache()
        let resolver = WeatherSnapshotFallbackResolver(
            cache: cache,
            currentUserID: { await owner.value }
        )
        let region = WeatherRegionKey(latitude: 40.7, longitude: -74.0)
        try await cache.store(Self.snapshot(observedAt: .now), ownerID: ownerID, region: region)

        do {
            _ = try await resolver.reading(
                ownerID: ownerID,
                region: region,
                fetch: { throw CancellationError() }
            )
            Issue.record("A cancelled weather request must remain cancelled.")
        } catch is CancellationError {
            // Expected: callers can stop weather work without a fallback result.
        }
    }

    @Test("Location must be recent and accurate before matching cached weather")
    func locationFreshnessBounds() {
        let now = Date.now
        let recent = Self.location(timestamp: now.addingTimeInterval(-5 * 60), accuracy: 200)
        let stale = Self.location(timestamp: now.addingTimeInterval(-16 * 60), accuracy: 200)
        let inaccurate = Self.location(timestamp: now, accuracy: 6_000)
        let future = Self.location(timestamp: now.addingTimeInterval(6 * 60), accuracy: 200)

        #expect(WeatherLocationFreshness.isUsable(recent, now: now))
        #expect(!WeatherLocationFreshness.isUsable(stale, now: now))
        #expect(!WeatherLocationFreshness.isUsable(inaccurate, now: now))
        #expect(!WeatherLocationFreshness.isUsable(future, now: now))
    }

    private static func location(timestamp: Date, accuracy: CLLocationAccuracy) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 100,
            timestamp: timestamp
        )
    }

    @Test("Owner change while a cache write is suspended prevents a live result")
    func ownerChangeDuringStoreFailsClosed() async throws {
        let ownerID = UUID()
        let peerID = UUID()
        let owner = WeatherTestCurrentOwner(ownerID)
        let cache = WeatherTestCache()
        await cache.setStoreAction { await owner.set(peerID) }
        let resolver = WeatherSnapshotFallbackResolver(
            cache: cache,
            currentUserID: { await owner.value }
        )

        do {
            _ = try await resolver.reading(
                ownerID: ownerID,
                region: WeatherRegionKey(latitude: 40.7, longitude: -74.0),
                fetch: { Self.snapshot(observedAt: .now) }
            )
            Issue.record("A result must not return after the account changes during persistence.")
        } catch let error as AstraError {
            #expect(error.category == .auth)
        }
    }

    @Test("Owner change while a cache read is suspended prevents fallback")
    func ownerChangeDuringLoadFailsClosed() async throws {
        let ownerID = UUID()
        let peerID = UUID()
        let owner = WeatherTestCurrentOwner(ownerID)
        let cache = WeatherTestCache()
        let region = WeatherRegionKey(latitude: 40.7, longitude: -74.0)
        try await cache.store(Self.snapshot(observedAt: .now), ownerID: ownerID, region: region)
        await cache.setLoadAction { await owner.set(peerID) }
        let resolver = WeatherSnapshotFallbackResolver(
            cache: cache,
            currentUserID: { await owner.value }
        )

        do {
            _ = try await resolver.reading(
                ownerID: ownerID,
                region: region,
                fetch: { throw AstraError.provider("offline") }
            )
            Issue.record("A cached result must not return after the account changes during load.")
        } catch let error as AstraError {
            #expect(error.category == .auth)
        }
    }

    @Test("Cancelled URL requests never return cached weather")
    func cancelledURLRequestDoesNotUseFallback() async throws {
        let ownerID = UUID()
        let owner = WeatherTestCurrentOwner(ownerID)
        let cache = WeatherTestCache()
        let region = WeatherRegionKey(latitude: 40.7, longitude: -74.0)
        try await cache.store(Self.snapshot(observedAt: .now), ownerID: ownerID, region: region)
        let resolver = WeatherSnapshotFallbackResolver(
            cache: cache,
            currentUserID: { await owner.value }
        )

        do {
            _ = try await resolver.reading(
                ownerID: ownerID,
                region: region,
                fetch: { throw URLError(.cancelled) }
            )
            Issue.record("A cancelled URL request must not be converted into a cache hit.")
        } catch let error as URLError {
            #expect(error.code == .cancelled)
        }
    }

    @Test("Cancellation after a provider returns still prevents a reading")
    func cancelledTaskAfterProviderReturnFailsClosed() async throws {
        let ownerID = UUID()
        let owner = WeatherTestCurrentOwner(ownerID)
        let cache = WeatherTestCache()
        let resolver = WeatherSnapshotFallbackResolver(
            cache: cache,
            currentUserID: { await owner.value }
        )
        let signal = WeatherTestStartSignal()
        let task = Task {
            try await resolver.reading(
                ownerID: ownerID,
                region: WeatherRegionKey(latitude: 40.7, longitude: -74.0),
                fetch: {
                    await signal.markStarted()
                    try? await Task.sleep(for: .seconds(30))
                    return Self.snapshot(observedAt: .now)
                }
            )
        }
        await signal.waitUntilStarted()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("A cancelled task must not return a provider result.")
        } catch is CancellationError {
            // Expected.
        }
        #expect(await cache.entryCount == 0)
    }

    private static func snapshot(observedAt: Date?) -> WeatherSnapshot {
        WeatherSnapshot(
            temperatureHigh: 70,
            temperatureLow: 55,
            condition: .partlyCloudy,
            precipitationChance: 0.1,
            observedAt: observedAt,
            temperatureCelsius: 18
        )
    }
}

private actor WeatherTestStartSignal {
    private var hasStarted = false
    private var waiter: CheckedContinuation<Void, Never>?

    func markStarted() {
        hasStarted = true
        waiter?.resume()
        waiter = nil
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private actor WeatherTestCurrentOwner {
    private(set) var value: UUID?

    init(_ value: UUID?) { self.value = value }

    func set(_ value: UUID?) { self.value = value }
}

private actor WeatherTestCache: WeatherSnapshotCaching {
    private struct Key: Hashable {
        let ownerID: UUID
        let region: WeatherRegionKey
    }

    private var values: [Key: WeatherSnapshot] = [:]
    private var storeAction: (@Sendable () async -> Void)?
    private var loadAction: (@Sendable () async -> Void)?

    var entryCount: Int { values.count }

    func setStoreAction(_ action: (@Sendable () async -> Void)?) { storeAction = action }
    func setLoadAction(_ action: (@Sendable () async -> Void)?) { loadAction = action }

    func store(_ snapshot: WeatherSnapshot, ownerID: UUID, region: WeatherRegionKey) async throws {
        guard let observedAt = snapshot.observedAt else { return }
        let age = Date.now.timeIntervalSince(observedAt)
        guard age <= FileWeatherSnapshotCache.maximumAge, age >= -5 * 60 else { return }
        values[Key(ownerID: ownerID, region: region)] = snapshot
        await storeAction?()
    }

    func load(ownerID: UUID, region: WeatherRegionKey, now: Date) async -> WeatherSnapshot? {
        await loadAction?()
        guard let snapshot = values[Key(ownerID: ownerID, region: region)],
              let observedAt = snapshot.observedAt else { return nil }
        let age = now.timeIntervalSince(observedAt)
        guard age <= FileWeatherSnapshotCache.maximumAge, age >= -5 * 60 else { return nil }
        return snapshot
    }

    func remove(ownerID: UUID) async throws {
        values = values.filter { $0.key.ownerID != ownerID }
    }
}
