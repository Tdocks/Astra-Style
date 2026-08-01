//
//  AstraReachability.swift
//  AstraStyle
//
//  A tiny `Network`-framework reachability monitor, shared app-wide. Used
//  by view models (starting with `HomeViewModel`) that need to show an
//  offline affordance alongside cached content (spec §7 "Cached closet
//  and outfits remain viewable"), and available to `OfflineMutationQueue`
//  conformances that want to opportunistically drain on reconnect.
//

import Foundation
import Network

public actor AstraReachability {
    public static let shared = AstraReachability()

    private let monitor = NWPathMonitor()
    private var currentStatus: NWPath.Status = .requiresConnection
    private var started = false
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    private init() {}

    public var isOffline: Bool {
        get async {
            startIfNeeded()
            return currentStatus != .satisfied
        }
    }

    public func connectivityUpdates() -> AsyncStream<Bool> {
        startIfNeeded()
        let id = UUID()
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        continuations[id] = continuation
        continuation.yield(currentStatus == .satisfied)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id: id) }
        }
        return stream
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.update(status: path.status) }
        }
        monitor.start(queue: DispatchQueue(label: "com.astrastyle.app.reachability"))
    }

    private func update(status: NWPath.Status) {
        currentStatus = status
        let isOnline = status == .satisfied
        for continuation in continuations.values {
            continuation.yield(isOnline)
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }
}
