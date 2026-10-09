import Foundation
import SwiftData
import Testing
@testable import AstraStyle

@Suite("Durable profile snapshots")
struct ProfileSnapshotPersistenceTests {
    @Test("A profile snapshot survives reopening and remains separated by owner")
    func profileSnapshotRoundTrips() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-profile-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("profiles.store")
        let ownerID = UUID()
        let otherOwnerID = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 100_123.456789)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 200_987.654321)
        let profile = Profile(id: ownerID, displayName: "Cached name", createdAt: createdAt, updatedAt: updatedAt)
        let style = StyleProfile(
            userID: ownerID,
            preferredColors: ["navy"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let body = BodyProfile(userID: ownerID, heightCm: 172.0, createdAt: createdAt, updatedAt: updatedAt)
        let lifestyle = LifestyleProfile(
            userID: ownerID,
            commonOccasions: ["work"],
            currency: "USD",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        let container = try AstraModelContainer.live(storeURL: storeURL)
        let cache = SwiftDataProfileSnapshotCache(modelContainer: container)
        try await cache.store(.profile(profile), pendingSync: false)
        try await cache.store(.style(style), pendingSync: true)
        try await cache.store(.body(body), pendingSync: false)
        try await cache.store(.lifestyle(lifestyle), pendingSync: false)

        let reopened = try AstraModelContainer.live(storeURL: storeURL)
        let reopenedCache = SwiftDataProfileSnapshotCache(modelContainer: reopened)
        let snapshot = try await reopenedCache.snapshot(for: ownerID)

        #expect(snapshot?.profile == profile)
        #expect(snapshot?.styleProfile == style)
        #expect(snapshot?.bodyProfile == body)
        #expect(snapshot?.lifestyleProfile == lifestyle)
        #expect(snapshot?.pendingStyle == true)
        #expect(try await reopenedCache.snapshot(for: otherOwnerID)?.isEmpty ?? true)
    }
}
