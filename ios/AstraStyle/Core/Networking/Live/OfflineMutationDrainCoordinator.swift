import Foundation

/// Serializes app-level reconnect/session-triggered drains for independent
/// repositories sharing one offline mutation queue.
public actor OfflineMutationDrainCoordinator {
    private let currentOwnerID: @Sendable () async -> UUID?
    private let drainCloset: @Sendable () async -> Void
    private let drainOutfits: @Sendable () async -> Void
    private let drainProfiles: @Sendable () async -> Void
    private let gate = AsyncOfflineMutationDrainGate()

    public init(
        currentOwnerID: @escaping @Sendable () async -> UUID?,
        drainCloset: @escaping @Sendable () async -> Void,
        drainOutfits: @escaping @Sendable () async -> Void,
        drainProfiles: @escaping @Sendable () async -> Void = {}
    ) {
        self.currentOwnerID = currentOwnerID
        self.drainCloset = drainCloset
        self.drainOutfits = drainOutfits
        self.drainProfiles = drainProfiles
    }

    /// Reachability streams may emit `true` at startup as well as on a
    /// reconnect. Both are useful; the owner lookup prevents signed-out work.
    public func connectivityChanged(isOnline: Bool) async {
        guard isOnline else { return }
        await drain(expectedOwnerID: nil)
    }

    /// Call when auth changes. A `nil` session never drains, and the owner is
    /// revalidated after acquiring the gate before any queued work is sent.
    public func sessionChanged(ownerID: UUID?) async {
        guard let ownerID else { return }
        await drain(expectedOwnerID: ownerID)
    }

    private func drain(expectedOwnerID: UUID?) async {
        let currentOwnerID = self.currentOwnerID
        let drainCloset = self.drainCloset
        let drainOutfits = self.drainOutfits
        let drainProfiles = self.drainProfiles
        await gate.withPermit {
            guard !Task.isCancelled,
                  let ownerID = await currentOwnerID(),
                  expectedOwnerID == nil || expectedOwnerID == ownerID else { return }

            await drainCloset()
            guard !Task.isCancelled, await currentOwnerID() == ownerID else { return }
            await drainOutfits()
            guard !Task.isCancelled, await currentOwnerID() == ownerID else { return }
            await drainProfiles()
        }
    }
}

/// A FIFO, cancellation-aware async mutex shared by queue drain callers.
/// Actor methods are reentrant while the apply closure awaits the network;
/// this gate prevents another repository from applying the same snapshot.
actor AsyncOfflineMutationDrainGate {
    private var isHeld = false
    private var waiterOrder: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

    var waitingCallerCount: Int { waiterOrder.count }

    func withPermit(_ operation: @Sendable () async -> Void) async {
        do {
            try await acquire()
        } catch {
            return
        }
        defer { release() }
        guard !Task.isCancelled else { return }
        await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if !isHeld {
            isHeld = true
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiterOrder.append(waiterID)
                    waiters[waiterID] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(waiterID) }
        }

        // A waiter can be granted the permit just as cancellation arrives.
        // Return it to the next waiter before propagating cancellation.
        if Task.isCancelled {
            release()
            throw CancellationError()
        }
    }

    private func cancel(_ waiterID: UUID) {
        guard let continuation = waiters.removeValue(forKey: waiterID) else { return }
        waiterOrder.removeAll { $0 == waiterID }
        continuation.resume(throwing: CancellationError())
    }

    private func release() {
        while !waiterOrder.isEmpty {
            let nextID = waiterOrder.removeFirst()
            guard let continuation = waiters.removeValue(forKey: nextID) else { continue }
            continuation.resume()
            return
        }
        isHeld = false
    }
}
