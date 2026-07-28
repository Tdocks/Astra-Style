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
}

public struct SystemNetworkReachabilityMonitor: NetworkReachabilityMonitoring {
    public init() {}

    public func isOffline() async -> Bool {
        await AstraReachability.shared.isOffline
    }
}
