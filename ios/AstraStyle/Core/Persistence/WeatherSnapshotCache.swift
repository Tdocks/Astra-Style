import Foundation

/// Coarse device-local location key. It intentionally retains only tenths of
/// a degree, never the precise coordinate used to query WeatherKit.
public struct WeatherRegionKey: Codable, Hashable, Sendable {
    public let latitudeTenthDegree: Int
    public let longitudeTenthDegree: Int

    public init(latitude: Double, longitude: Double) {
        latitudeTenthDegree = Int((latitude * 10).rounded())
        longitudeTenthDegree = Int((longitude * 10).rounded())
    }
}

public protocol WeatherSnapshotCacheInvalidating: Sendable {
    func clearCachedWeather(ownerID: UUID) async
}

public protocol WeatherSnapshotCaching: Sendable {
    func store(_ snapshot: WeatherSnapshot, ownerID: UUID, region: WeatherRegionKey) async throws
    func load(ownerID: UUID, region: WeatherRegionKey, now: Date) async -> WeatherSnapshot?
    func remove(ownerID: UUID) async throws
}

/// File-protected, owner-scoped last-known WeatherKit reading. Data remains in
/// Application Support and is never synced or included in API payloads.
public actor FileWeatherSnapshotCache: WeatherSnapshotCaching {
    public static let maximumAge: TimeInterval = 2 * 60 * 60
    private static let maximumFutureSkew: TimeInterval = 5 * 60

    private struct Entry: Codable {
        let schemaVersion: Int
        let ownerID: UUID
        let region: WeatherRegionKey
        let snapshot: WeatherSnapshot
    }

    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder.astraDefault
    private let decoder = JSONDecoder.astraDefault

    public init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("AstraStyle/Weather", isDirectory: true)
        self.fileManager = fileManager
    }

    public func store(_ snapshot: WeatherSnapshot, ownerID: UUID, region: WeatherRegionKey) async throws {
        guard let observedAt = snapshot.observedAt else { return }
        let age = Date.now.timeIntervalSince(observedAt)
        guard age <= Self.maximumAge, age >= -Self.maximumFutureSkew else { return }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        var protectedDirectoryURL = directoryURL
        try protectedDirectoryURL.setResourceValues(directoryValues)

        let entry = Entry(schemaVersion: 1, ownerID: ownerID, region: region, snapshot: snapshot)
        let data = try encoder.encode(entry)
        let destination = fileURL(for: ownerID)
        try data.write(to: destination, options: .atomic)
        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )
            var fileValues = URLResourceValues()
            fileValues.isExcludedFromBackup = true
            var protectedFileURL = destination
            try protectedFileURL.setResourceValues(fileValues)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    public func load(ownerID: UUID, region: WeatherRegionKey, now: Date = .now) async -> WeatherSnapshot? {
        let source = fileURL(for: ownerID)
        guard let data = try? Data(contentsOf: source),
              let entry = try? decoder.decode(Entry.self, from: data),
              entry.schemaVersion == 1,
              entry.ownerID == ownerID,
              entry.region == region,
              let observedAt = entry.snapshot.observedAt else { return nil }

        let age = now.timeIntervalSince(observedAt)
        guard age <= Self.maximumAge, age >= -Self.maximumFutureSkew else { return nil }
        return entry.snapshot
    }

    public func remove(ownerID: UUID) async throws {
        let url = fileURL(for: ownerID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func fileURL(for ownerID: UUID) -> URL {
        directoryURL.appendingPathComponent("weather-\(ownerID.uuidString.lowercased()).json")
    }
}

/// Resolves live weather first and uses the last-known value only after a
/// provider failure, only for the active owner, and only for the same coarse
/// location. Owner identity is rechecked across the provider suspension.
public struct WeatherSnapshotFallbackResolver: Sendable {
    private let cache: any WeatherSnapshotCaching
    private let currentUserID: @Sendable () async -> UUID?

    public init(
        cache: any WeatherSnapshotCaching,
        currentUserID: @escaping @Sendable () async -> UUID?
    ) {
        self.cache = cache
        self.currentUserID = currentUserID
    }

    public func reading(
        ownerID: UUID?,
        region: WeatherRegionKey,
        now: Date = .now,
        fetch: @Sendable () async throws -> WeatherSnapshot
    ) async throws -> WeatherReading {
        try await ensureOwner(ownerID)
        do {
            let snapshot = try await fetch()
            try await ensureOwner(ownerID)
            try await persistIfOwned(snapshot, ownerID: ownerID, region: region)
            return WeatherReading(snapshot: snapshot, source: .live)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch let error as AstraError where error.category == .auth {
            throw error
        } catch {
            return try await lastKnownReading(
                ownerID: ownerID,
                region: region,
                now: now,
                providerError: error
            )
        }
    }

    private func ensureOwner(_ ownerID: UUID?) async throws {
        try Task.checkCancellation()
        guard await currentUserID() == ownerID else {
            throw AstraError.auth("Your account changed while checking the weather.")
        }
        try Task.checkCancellation()
    }

    private func persistIfOwned(
        _ snapshot: WeatherSnapshot,
        ownerID: UUID?,
        region: WeatherRegionKey
    ) async throws {
        guard let ownerID else { return }
        do {
            try await cache.store(snapshot, ownerID: ownerID, region: region)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            // A cache write failure does not discard a live forecast.
        }
        try await ensureOwner(ownerID)
    }

    private func lastKnownReading(
        ownerID: UUID?,
        region: WeatherRegionKey,
        now: Date,
        providerError: any Error
    ) async throws -> WeatherReading {
        try await ensureOwner(ownerID)
        guard let ownerID else { throw providerError }
        let snapshot = await cache.load(ownerID: ownerID, region: region, now: now)
        try await ensureOwner(ownerID)
        guard let snapshot else { throw providerError }
        return WeatherReading(snapshot: snapshot, source: .lastKnown)
    }
}
