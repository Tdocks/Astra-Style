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

/// Location authorization for weather, read WITHOUT prompting.
///
/// Exists so a caller can decide whether to show spec §7's explanation
/// ("Location: when enabling weather") before ever touching
/// `requestLocationPermissionIfNeeded()` — that method is safe to call at
/// any time (it only shows the system dialog when the answer is
/// `.notDetermined`), but "safe to call" is not the same as "safe to call
/// with no context on screen". `HomeViewModel.enableWeather()` is the only
/// place in the app that calls `requestLocationPermissionIfNeeded()`, and
/// it only does so after `WeatherOptInCardView` has already explained why.
public enum WeatherLocationAuthorization: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

public protocol WeatherService: Sendable {
    /// Current authorization, read without prompting.
    func currentAuthorization() -> WeatherLocationAuthorization

    /// Requests location permission only in context (spec §7 "Location:
    /// when enabling weather"), never at launch. Returns whether
    /// permission is now granted. Does not itself present any explanation
    /// — showing one before this is called is the caller's job (see
    /// `currentAuthorization()`'s doc comment).
    func requestLocationPermissionIfNeeded() async -> Bool

    /// Current conditions for the user's location. Throws `AstraError` if
    /// permission was denied or the lookup failed — callers should treat
    /// that as "show the calendar/weather-denied empty state"
    /// (spec §21 "Calendar denied" pattern applies symmetrically to
    /// weather).
    func currentSnapshot() async throws -> WeatherSnapshot
}
