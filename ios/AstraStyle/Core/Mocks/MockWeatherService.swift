//
//  MockWeatherService.swift
//  AstraStyle
//
//  In-memory `WeatherService` for previews/tests (spec §31).
//

import Foundation

public struct MockWeatherService: WeatherService {
    public var snapshot: WeatherSnapshot
    public var permissionGranted: Bool

    public init(snapshot: WeatherSnapshot = SampleData.weatherSnapshot, permissionGranted: Bool = true) {
        self.snapshot = snapshot
        self.permissionGranted = permissionGranted
    }

    public func requestLocationPermissionIfNeeded() async -> Bool { permissionGranted }

    public func currentSnapshot() async throws -> WeatherSnapshot {
        guard permissionGranted else {
            throw AstraError.auth("Location access is off, so Kyra can't check today's weather.")
        }
        return snapshot
    }
}
