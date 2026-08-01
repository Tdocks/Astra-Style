//
//  NetworkReachabilityMonitoring.swift
//  AstraStyle
//
//  A minimal reachability seam so view models never import `Network`
//  directly, and so tests can inject a fixed online/offline answer instead
//  of depending on the real `AstraReachability` singleton. Originally
//  declared inside `Features/Home/ViewModels/HomeViewModel.swift` with a
//  note to promote it here once a second feature needed it —
//  `Features/Slice` is that second feature.
//

import Foundation

public protocol NetworkReachabilityMonitoring: Sendable {
    func isOffline() async -> Bool
    /// Emits `true` when the device is online and `false` when it is offline.
    func connectivityUpdates() -> AsyncStream<Bool>
}

extension NetworkReachabilityMonitoring {
    public func connectivityUpdates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(!(await isOffline()))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public struct SystemNetworkReachabilityMonitor: NetworkReachabilityMonitoring {
    public init() {}

    public func isOffline() async -> Bool {
        await AstraReachability.shared.isOffline
    }

    public func connectivityUpdates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                let stream = await AstraReachability.shared.connectivityUpdates()
                for await isOnline in stream {
                    continuation.yield(isOnline)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public struct StaticNetworkReachabilityMonitor: NetworkReachabilityMonitoring {
    private let offline: Bool

    public init(offline: Bool = false) {
        self.offline = offline
    }

    public func isOffline() async -> Bool {
        offline
    }
}
