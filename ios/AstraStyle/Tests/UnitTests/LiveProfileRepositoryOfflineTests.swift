import Foundation
import SwiftData
import Testing
@testable import AstraStyle

@Suite("Live profile repository offline cache and edits")
struct LiveProfileRepositoryOfflineTests {
    @Test("Queued profile values preserve every timestamp across serialization")
    func queuedProfileDatesAreLossless() throws {
        let ownerID = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 100_123.456789)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 200_987.654321)
        let profile = Profile(id: ownerID, createdAt: createdAt, updatedAt: updatedAt)
        let mutation = try ProfileOfflineMutation(ownerID: ownerID, value: .profile(profile))
        let envelope = try JSONEncoder.astraDefault.encode(mutation)
        let reopened = try JSONDecoder.astraDefault.decode(ProfileOfflineMutation.self, from: envelope)

        guard case .profile(let restored) = try reopened.decodedValue() else {
            Issue.record("Expected a queued profile value")
            return
        }
        #expect(restored == profile)
        #expect(restored.createdAt.timeIntervalSinceReferenceDate == createdAt.timeIntervalSinceReferenceDate)
        #expect(restored.updatedAt.timeIntervalSinceReferenceDate == updatedAt.timeIntervalSinceReferenceDate)
    }

    @Test("An accepted offline edit is durable, visible from cache, and replayed when the writer recovers")
    func offlineEditReplays() async throws {
        let ownerID = UUID()
        let writer = StubProfileWriter(ownerID: ownerID, offline: true)
        let cache = InMemoryProfileSnapshotCache()
        let queue = InMemoryOfflineMutationQueue()
        let repository = makeRepository(ownerID: ownerID, writer: writer, cache: cache, queue: queue)
        let original = Profile(id: ownerID, displayName: "Before")

        try await cache.store(.profile(original), pendingSync: false)
        let edited = try await repository.updateProfile(original)

        #expect(edited.displayName == "Before")
        #expect(await queue.pendingMutations().count == 1)
        #expect(try await repository.fetchCurrentProfile().displayName == "Before")

        await writer.setOffline(false)
        await repository.drainPendingMutations()

        #expect(await queue.pendingMutations().isEmpty)
        #expect(await writer.writeCount == 1)
        #expect(try await cache.snapshot(for: ownerID)?.pendingProfile == false)
    }

    @Test("A reopened profile cache returns before a suspended network refresh completes")
    func reopenedCacheReturnsBeforeRefreshCompletes() async throws {
        let (directory, storeURL) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ownerID = UUID()
        let cachedProfile = Profile(id: ownerID, displayName: "On disk")

        do {
            let container = try AstraModelContainer.live(storeURL: storeURL)
            let cache = SwiftDataProfileSnapshotCache(modelContainer: container)
            try await cache.store(.profile(cachedProfile), pendingSync: false)
        }

        let reopened = try AstraModelContainer.live(storeURL: storeURL)
        let cache = SwiftDataProfileSnapshotCache(modelContainer: reopened)
        let writer = SuspendedProfileWriter(ownerID: ownerID)
        let repository = makeRepository(ownerID: ownerID, writer: writer, cache: cache)
        let result = ProfileFetchResult()
        let fetchTask = Task {
            let profile = try await repository.fetchCurrentProfile()
            await result.finish(profile)
            return profile
        }

        await writer.waitUntilFetchStarts()
        try await Task.sleep(for: .milliseconds(100))
        let returned = await result.profile
        #expect(returned == cachedProfile)

        await writer.releaseFetch()
        #expect(try await fetchTask.value == cachedProfile)
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while repository.refreshLock.withLock({ !repository.activeRefreshes.isEmpty }), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(repository.refreshLock.withLock { repository.activeRefreshes.isEmpty })
        #expect(try await cache.snapshot(for: ownerID)?.profile?.displayName == "Remote")
    }

    @Test("Offline edits to all four profile tables survive relaunch and replay from disk")
    func allProfileEditsReplayAfterRelaunch() async throws {
        let (directory, storeURL) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ownerID = UUID()
        let timestamp = Date(timeIntervalSinceReferenceDate: 300_000)
        let editedProfile = Profile(id: ownerID, displayName: "Edited name", createdAt: timestamp, updatedAt: timestamp)
        let editedStyle = StyleProfile(
            userID: ownerID,
            styleGoals: ["dress with more color"],
            preferredColors: ["cobalt"],
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let editedBody = BodyProfile(userID: ownerID, heightCm: 181, shoeSize: "43", createdAt: timestamp, updatedAt: timestamp)
        let editedLifestyle = LifestyleProfile(
            userID: ownerID,
            commonOccasions: ["travel"],
            currency: "CAD",
            sustainabilityPreference: "repair first",
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try await persistOfflineEdits(
            ownerID: ownerID,
            storeURL: storeURL,
            edits: ProfileEditSet(
                profile: editedProfile,
                style: editedStyle,
                body: editedBody,
                lifestyle: editedLifestyle
            )
        )

        let reopened = try AstraModelContainer.live(storeURL: storeURL)
        let cache = SwiftDataProfileSnapshotCache(modelContainer: reopened)
        let queue = SwiftDataOfflineMutationQueue(modelContainer: reopened)
        let writer = DurableReplayProfileWriter(ownerID: ownerID, offline: false)
        let repository = makeRepository(ownerID: ownerID, writer: writer, cache: cache, queue: queue)

        await repository.drainPendingMutations()

        #expect(await queue.pendingMutations().isEmpty)
        #expect(await writer.replayedTables == [.profile, .style, .body, .lifestyle])
        let snapshot = try await cache.snapshot(for: ownerID)
        #expect(snapshot?.profile?.displayName == "Edited name")
        #expect(snapshot?.styleProfile?.preferredColors == ["cobalt"])
        #expect(snapshot?.bodyProfile?.heightCm == 181)
        #expect(snapshot?.lifestyleProfile?.sustainabilityPreference == "repair first")
        #expect(snapshot?.pendingProfile == false)
        #expect(snapshot?.pendingStyle == false)
        #expect(snapshot?.pendingBody == false)
        #expect(snapshot?.pendingLifestyle == false)
    }

    @Test("A profile snapshot is isolated by owner")
    func cacheIsOwnerScoped() async throws {
        let ownerID = UUID()
        let otherOwnerID = UUID()
        let cache = InMemoryProfileSnapshotCache()
        let ownerProfile = Profile(id: ownerID, displayName: "Owner")
        try await cache.store(.profile(ownerProfile), pendingSync: false)
        let writer = StubProfileWriter(ownerID: otherOwnerID)
        let repository = makeRepository(ownerID: otherOwnerID, writer: writer, cache: cache)

        let loaded = try await repository.fetchCurrentProfile()

        #expect(loaded.id == otherOwnerID)
        #expect(loaded.displayName == nil)
        #expect(try await cache.snapshot(for: ownerID)?.profile?.displayName == "Owner")
    }

    @Test("A queued profile mutation cannot replay under another signed-in owner")
    func queuedEditStaysWithOriginalOwner() async throws {
        let ownerID = UUID()
        let queue = InMemoryOfflineMutationQueue()
        let payload = try ProfileOfflineMutation(
            ownerID: ownerID,
            value: .profile(Profile(id: ownerID, displayName: "Pending"))
        )
        try await queue.enqueue(OfflineMutation(
            entity: .profile,
            operation: .update,
            payloadData: try JSONEncoder.astraDefault.encode(payload)
        ))
        let writer = StubProfileWriter(ownerID: ownerID)
        let repository = makeRepository(ownerID: UUID(), writer: writer, queue: queue)

        await repository.drainPendingMutations()

        #expect(await queue.pendingMutations().count == 1)
        #expect(await writer.writeCount == 0)
    }

    @Test("A profile edit is rejected when durable queue insertion fails")
    func queueFailureRejectsEdit() async throws {
        let ownerID = UUID()
        let cache = InMemoryProfileSnapshotCache()
        let repository = LiveProfileRepository(
            apiClient: AstraAPIClient(environment: .preview),
            supabase: AstraSupabaseClientFactory.previewClient,
            profileWriter: StubProfileWriter(ownerID: ownerID, offline: true),
            profileCache: cache,
            offlineQueue: FailingProfileQueue(),
            currentUserID: { ownerID }
        )
        let profile = Profile(id: ownerID, displayName: "Never accepted")

        await #expect(throws: (any Error).self) {
            try await repository.updateProfile(profile)
        }
        #expect(try await cache.snapshot(for: ownerID)?.isEmpty ?? true)
    }

    private func makeRepository(
        ownerID: UUID,
        writer: any ProfileWriting,
        cache: (any ProfileSnapshotCaching)? = nil,
        queue: (any OfflineMutationQueue)? = nil
    ) -> LiveProfileRepository {
        LiveProfileRepository(
            apiClient: AstraAPIClient(environment: .preview),
            supabase: AstraSupabaseClientFactory.previewClient,
            profileWriter: writer,
            profileCache: cache ?? InMemoryProfileSnapshotCache(),
            offlineQueue: queue ?? InMemoryOfflineMutationQueue(),
            currentUserID: { ownerID }
        )
    }

    private func makeTemporaryStore() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-profile-offline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("profiles.store"))
    }

    private func persistOfflineEdits(
        ownerID: UUID,
        storeURL: URL,
        edits: ProfileEditSet
    ) async throws {
        let container = try AstraModelContainer.live(storeURL: storeURL)
        let cache = SwiftDataProfileSnapshotCache(modelContainer: container)
        let queue = SwiftDataOfflineMutationQueue(modelContainer: container)
        try await cache.store(.profile(Profile(id: ownerID, displayName: "Original")), pendingSync: false)
        try await cache.store(.style(StyleProfile(userID: ownerID)), pendingSync: false)
        try await cache.store(.body(BodyProfile(userID: ownerID)), pendingSync: false)
        try await cache.store(.lifestyle(LifestyleProfile(userID: ownerID)), pendingSync: false)

        let repository = makeRepository(
            ownerID: ownerID,
            writer: DurableReplayProfileWriter(ownerID: ownerID, offline: true),
            cache: cache,
            queue: queue
        )
        _ = try await repository.updateProfile(edits.profile)
        _ = try await repository.updateStyleProfile(edits.style)
        _ = try await repository.updateBodyProfile(edits.body)
        _ = try await repository.updateLifestyleProfile(edits.lifestyle)
        #expect(await queue.pendingMutations().count == 4)
    }
}

private actor ProfileFetchResult {
    private(set) var profile: Profile?

    func finish(_ value: Profile) { profile = value }
}

private struct ProfileEditSet {
    let profile: Profile
    let style: StyleProfile
    let body: BodyProfile
    let lifestyle: LifestyleProfile
}

private actor SuspendedProfileWriter: ProfileWriting {
    private let ownerID: UUID
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var fetchContinuation: CheckedContinuation<Profile, Never>?

    init(ownerID: UUID) { self.ownerID = ownerID }

    func waitUntilFetchStarts() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseFetch() { fetchContinuation?.resume(returning: Profile(id: ownerID, displayName: "Remote")) }

    func fetchProfile(ownerID: UUID) async throws -> Profile {
        guard ownerID == self.ownerID else { throw AstraError.auth("wrong owner") }
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return await withCheckedContinuation { fetchContinuation = $0 }
    }

    func fetchStyleProfile(ownerID: UUID) async throws -> StyleProfile? { nil }
    func fetchBodyProfile(ownerID: UUID) async throws -> BodyProfile? { nil }
    func fetchLifestyleProfile(ownerID: UUID) async throws -> LifestyleProfile? { nil }
    func updateProfile(_ value: Profile) async throws -> Profile { value }
    func upsertStyleProfile(_ value: StyleProfile) async throws -> StyleProfile { value }
    func upsertBodyProfile(_ value: BodyProfile) async throws -> BodyProfile { value }
    func upsertLifestyleProfile(_ value: LifestyleProfile) async throws -> LifestyleProfile { value }
}

private actor DurableReplayProfileWriter: ProfileWriting {
    private let ownerID: UUID
    private var offline: Bool
    private(set) var replayedTables: Set<ProfileOfflineMutation.Table> = []

    init(ownerID: UUID, offline: Bool) {
        self.ownerID = ownerID
        self.offline = offline
    }

    func fetchProfile(ownerID: UUID) async throws -> Profile {
        try check(ownerID)
        return Profile(id: ownerID, updatedAt: .distantPast)
    }

    func fetchStyleProfile(ownerID: UUID) async throws -> StyleProfile? { try check(ownerID); return nil }
    func fetchBodyProfile(ownerID: UUID) async throws -> BodyProfile? { try check(ownerID); return nil }
    func fetchLifestyleProfile(ownerID: UUID) async throws -> LifestyleProfile? { try check(ownerID); return nil }

    func updateProfile(_ value: Profile) async throws -> Profile {
        try check(value.id)
        replayedTables.insert(.profile)
        return value
    }

    func upsertStyleProfile(_ value: StyleProfile) async throws -> StyleProfile {
        try check(value.userID)
        replayedTables.insert(.style)
        return value
    }

    func upsertBodyProfile(_ value: BodyProfile) async throws -> BodyProfile {
        try check(value.userID)
        replayedTables.insert(.body)
        return value
    }

    func upsertLifestyleProfile(_ value: LifestyleProfile) async throws -> LifestyleProfile {
        try check(value.userID)
        replayedTables.insert(.lifestyle)
        return value
    }

    private func check(_ candidateOwnerID: UUID) throws {
        guard candidateOwnerID == ownerID else { throw AstraError.auth("wrong owner") }
        guard !offline else { throw AstraError.network("offline") }
    }
}

private actor FailingProfileQueue: OfflineMutationQueue {
    func enqueue(_ mutation: OfflineMutation) async throws {
        throw AstraError.server("queue persistence failed")
    }
    func pendingMutations() async -> [OfflineMutation] { [] }
    func drain(apply: @Sendable (OfflineMutation) async throws -> Void) async {}
    func remove(id: UUID) async {}
    func clear() async {}
}

private actor StubProfileWriter: ProfileWriting {
    private let ownerID: UUID
    private var offline: Bool
    private var profile: Profile
    private(set) var writeCount = 0

    init(ownerID: UUID, offline: Bool = false) {
        self.ownerID = ownerID
        self.offline = offline
        profile = Profile(id: ownerID)
    }

    func setOffline(_ value: Bool) { offline = value }

    func fetchProfile(ownerID: UUID) async throws -> Profile {
        guard ownerID == self.ownerID else { throw AstraError.auth("wrong owner") }
        if offline { throw AstraError.network("offline") }
        return profile
    }

    func fetchStyleProfile(ownerID: UUID) async throws -> StyleProfile? { nil }
    func fetchBodyProfile(ownerID: UUID) async throws -> BodyProfile? { nil }
    func fetchLifestyleProfile(ownerID: UUID) async throws -> LifestyleProfile? { nil }

    func updateProfile(_ value: Profile) async throws -> Profile {
        guard value.id == ownerID else { throw AstraError.auth("wrong owner") }
        if offline { throw AstraError.network("offline") }
        writeCount += 1
        profile = value
        return value
    }

    func upsertStyleProfile(_ value: StyleProfile) async throws -> StyleProfile {
        if offline { throw AstraError.network("offline") }
        writeCount += 1
        return value
    }

    func upsertBodyProfile(_ value: BodyProfile) async throws -> BodyProfile {
        if offline { throw AstraError.network("offline") }
        writeCount += 1
        return value
    }

    func upsertLifestyleProfile(_ value: LifestyleProfile) async throws -> LifestyleProfile {
        if offline { throw AstraError.network("offline") }
        writeCount += 1
        return value
    }
}
