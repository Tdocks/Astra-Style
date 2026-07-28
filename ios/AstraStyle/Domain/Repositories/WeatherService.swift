//
//  WeatherService.swift
//  AstraStyle
//
//  Weather context for Kyra's Daily Brief (spec §6.11 header) and outfit
//  generation (spec §5.4). Spec §8 allows either WeatherKit or a server
//  weather provider — the protocol is intentionally silent on which, so
//  the `.live()` implementation can pick WeatherKit today and move the
//  lookup server-side later without touching a single call site.
//

import Foundation

public protocol WeatherService: Sendable {
    /// Requests location permission only in context (spec §7 "Location:
    /// when enabling weather"), never at launch. Returns whether
    /// permission is now granted.
    func requestLocationPermissionIfNeeded() async -> Bool

    /// Current conditions for the user's location. Throws `AstraError` if
    /// permission was denied or the lookup failed — callers should treat
    /// that as "show the calendar/weather-denied empty state"
    /// (spec §21 "Calendar denied" pattern applies symmetrically to
    /// weather).
    func currentSnapshot() async throws -> WeatherSnapshot
}
