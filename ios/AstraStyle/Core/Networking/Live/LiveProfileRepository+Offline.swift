import Foundation
import OSLog

extension LiveProfileRepository {
    private static var profileLogger: Logger {
        Logger(subsystem: "com.astra.style", category: "ProfileOfflineSync")
    }

    public func drainPendingMutations() async {
        await offlineQueue.drain { [profileWriter, profileCache, currentUserID] mutation in
            guard mutation.entity == .profile else { throw OfflineMutationNotHandled() }
            guard mutation.operation == .update else {
                throw AstraError.validation("A queued profile change has an unsupported operation.")
            }
            let payload: ProfileOfflineMutation
            do {
                payload = try JSONDecoder.astraDefault.decode(ProfileOfflineMutation.self, from: mutation.payloadData)
            } catch {
                throw AstraError.server("A queued profile change couldn't be read and has been kept for recovery.")
            }
            guard await currentUserID() == payload.ownerID else { throw OfflineMutationNotHandled() }
            let local = try payload.decodedValue()
            guard local.ownerID == payload.ownerID else {
                throw AstraError.auth("A queued profile change belongs to another account.")
            }

            let remote = try await Self.fetchProfileValue(payload.table, ownerID: payload.ownerID, writer: profileWriter)
            guard await currentUserID() == payload.ownerID else { throw OfflineMutationNotHandled() }
            guard remote == nil || remote?.ownerID == payload.ownerID else {
                throw AstraError.auth("A profile update returned data for another account. The queued edit has been kept.")
            }
            if let remote, Self.updatedAt(remote) > payload.updatedAt {
                try await profileCache.store(remote, pendingSync: false)
                return
            }

            let saved = try await Self.writeProfileValue(local, writer: profileWriter)
            guard await currentUserID() == payload.ownerID, saved.ownerID == payload.ownerID else {
                throw OfflineMutationNotHandled()
            }
            try await profileCache.store(saved, pendingSync: false)
        }
    }

    public func purgeLocalProfileCache(ownerID: UUID) async throws {
        for mutation in await offlineQueue.pendingMutations() where mutation.entity == .profile {
            guard Self.decodeMutationOwner(mutation.payloadData) == ownerID else { continue }
            await offlineQueue.remove(id: mutation.id)
        }
        let remainingMutations = await offlineQueue.pendingMutations()
        let retainedOwnerMutations = remainingMutations.contains { mutation in
            mutation.entity == .profile && Self.decodeMutationOwner(mutation.payloadData) == ownerID
        }
        guard !retainedOwnerMutations else {
            throw AstraError.server("Local profile edits couldn't be removed. Retry account cleanup before continuing.")
        }
        try await profileCache.removeAll(ownerID: ownerID)
    }

    func requireOwner(_ expectedOwnerID: UUID? = nil) async throws -> UUID {
        guard let ownerID = await currentUserID() else {
            throw AstraError.auth("Sign in again to access your profile.")
        }
        guard expectedOwnerID == nil || expectedOwnerID == ownerID else {
            throw AstraError.auth("Profile changes belong to another account.")
        }
        return ownerID
    }

    func verifyCurrentOwner(_ ownerID: UUID) async throws {
        guard await currentUserID() == ownerID else {
            throw AstraError.auth("Your account changed while loading profile data. Please try again.")
        }
    }

    func queueProfileValue(_ value: ProfileSnapshotValue, table: ProfileOfflineMutation.Table) async throws {
        let ownerID = try await requireOwner(value.ownerID)
        let payload = try ProfileOfflineMutation(ownerID: ownerID, value: value)
        guard payload.table == table else { throw AstraError.validation("The profile change type did not match its payload.") }
        let mutation = OfflineMutation(
            entity: .profile,
            operation: .update,
            payloadData: try JSONEncoder.astraDefault.encode(payload)
        )
        try await offlineQueue.enqueue(mutation)
        do {
            try await profileCache.store(value, pendingSync: true)
        } catch {
            // The durable queue contains the full value and overlays it into
            // future reads, so cache-write failure cannot lose this edit.
            Self.profileLogger.error("Profile cache write failed after durable queue insertion: \(String(describing: error), privacy: .private)")
        }
        await drainPendingMutations()
    }

    func pendingAwareSnapshot(for ownerID: UUID) async throws -> ProfileSnapshot {
        var snapshot = try await profileCache.snapshot(for: ownerID) ?? ProfileSnapshot()
        for mutation in await offlineQueue.pendingMutations() where mutation.entity == .profile {
            guard let payload = Self.decodeMutationOwner(mutation.payloadData), payload == ownerID else { continue }
            guard let payload = try? JSONDecoder.astraDefault.decode(ProfileOfflineMutation.self, from: mutation.payloadData) else {
                throw AstraError.server("A pending profile edit couldn't be read. It has been kept for recovery.")
            }
            guard mutation.operation == .update else {
                throw AstraError.server("A queued profile change has an unsupported operation.")
            }
            let value: ProfileSnapshotValue
            do {
                value = try payload.decodedValue()
            } catch {
                throw AstraError.server("A pending profile edit couldn't be read. It has been kept for recovery.")
            }
            guard value.ownerID == ownerID else { throw AstraError.auth("A pending profile edit belongs to another account.") }
            snapshot.apply(value, pending: true)
        }
        return snapshot
    }

    func scheduleRefresh(table: ProfileOfflineMutation.Table, ownerID: UUID) {
        let key = "\(ownerID.uuidString):\(table.rawValue)"
        let shouldRefresh = refreshLock.withLock { activeRefreshes.insert(key).inserted }
        guard shouldRefresh else { return }
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.refreshLock.withLock { _ = self.activeRefreshes.remove(key) }
            }
            do {
                guard await self.currentUserID() == ownerID else { return }
                let remote = try await Self.fetchProfileValue(table, ownerID: ownerID, writer: self.profileWriter)
                guard await self.currentUserID() == ownerID else { return }
                guard remote == nil || remote?.ownerID == ownerID else {
                    throw AstraError.auth("Profile refresh returned data for another account.")
                }
                let value = remote ?? Self.missingValue(table, ownerID: ownerID)
                try await self.profileCache.mergeRemote(value)
            } catch {
                Self.profileLogger.debug("Profile background refresh failed; cached data remains available.")
            }
        }
    }

    private static func fetchProfileValue(
        _ table: ProfileOfflineMutation.Table,
        ownerID: UUID,
        writer: any ProfileWriting
    ) async throws -> ProfileSnapshotValue? {
        return switch table {
        case .profile: .profile(try await writer.fetchProfile(ownerID: ownerID))
        case .style: try await writer.fetchStyleProfile(ownerID: ownerID).map(ProfileSnapshotValue.style)
        case .body: try await writer.fetchBodyProfile(ownerID: ownerID).map(ProfileSnapshotValue.body)
        case .lifestyle: try await writer.fetchLifestyleProfile(ownerID: ownerID).map(ProfileSnapshotValue.lifestyle)
        }
    }

    private static func missingValue(
        _ table: ProfileOfflineMutation.Table,
        ownerID: UUID
    ) -> ProfileSnapshotValue {
        return switch table {
        case .profile: .profile(Profile(id: ownerID))
        case .style: .styleMissing(ownerID: ownerID)
        case .body: .bodyMissing(ownerID: ownerID)
        case .lifestyle: .lifestyleMissing(ownerID: ownerID)
        }
    }

    private static func writeProfileValue(
        _ value: ProfileSnapshotValue,
        writer: any ProfileWriting
    ) async throws -> ProfileSnapshotValue {
        return switch value {
        case .profile(let value): .profile(try await writer.updateProfile(value))
        case .style(let value): .style(try await writer.upsertStyleProfile(value))
        case .body(let value): .body(try await writer.upsertBodyProfile(value))
        case .lifestyle(let value): .lifestyle(try await writer.upsertLifestyleProfile(value))
        case .styleMissing, .bodyMissing, .lifestyleMissing:
            throw AstraError.validation("An empty profile cannot be synchronized as an edit.")
        }
    }

    private static func updatedAt(_ value: ProfileSnapshotValue) -> Date {
        return switch value {
        case .profile(let value): value.updatedAt
        case .style(let value): value.updatedAt
        case .body(let value): value.updatedAt
        case .lifestyle(let value): value.updatedAt
        case .styleMissing, .bodyMissing, .lifestyleMissing: .distantPast
        }
    }

    private static func decodeMutationOwner(_ data: Data) -> UUID? {
        struct OwnerEnvelope: Decodable { let ownerID: UUID }
        return try? JSONDecoder.astraDefault.decode(OwnerEnvelope.self, from: data).ownerID
    }
}
