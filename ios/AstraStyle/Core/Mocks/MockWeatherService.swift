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

    /// Defaults to matching `permissionGranted` (`.authorized`/`.denied`) so
    /// existing call sites that only set `permissionGranted` keep working
    /// unchanged. Pass `.notDetermined` explicitly to exercise Home's
    /// "enable weather" explanation, which only shows before any decision
    /// exists — `permissionGranted` alone has no way to express that third
    /// state.
    public var authorization: WeatherLocationAuthorization

    public init(
        snapshot: WeatherSnapshot = SampleData.weatherSnapshot,
        permissionGranted: Bool = true,
        authorization: WeatherLocationAuthorization? = nil
    ) {
        self.snapshot = snapshot
        self.permissionGranted = permissionGranted
        self.authorization = authorization ?? (permissionGranted ? .authorized : .denied)
    }

    public func currentAuthorization() -> WeatherLocationAuthorization { authorization }

    public func requestLocationPermissionIfNeeded() async -> Bool { permissionGranted }

    public func currentSnapshot() async throws -> WeatherSnapshot {
        guard permissionGranted else {
            throw AstraError.auth("Location access is off, so Kyra can't check today's weather.")
        }
        return snapshot
    }
}
