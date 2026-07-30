//
//  LiveWeatherService.swift
//  AstraStyle
//
//  WeatherKit-backed `WeatherService` (spec §8). Location permission is
//  requested only when the user enables weather-aware recommendations
//  (spec §7 "Location: when enabling weather"), never at launch.
//

import CoreLocation
import Foundation
import WeatherKit

public final class LiveWeatherService: NSObject, WeatherService, CLLocationManagerDelegate, @unchecked Sendable {
    private let locationManager = CLLocationManager()
    private let weatherKitService = WeatherKit.WeatherService.shared

    // Guards `authorizationContinuation`, which is written from whatever
    // arbitrary thread calls `requestLocationPermissionIfNeeded()` and
    // resumed from CLLocationManager's delegate callback thread.
    private let continuationLock = NSLock()
    private var authorizationContinuation: CheckedContinuation<Bool, Never>?

    public override init() {
        super.init()
        locationManager.delegate = self
    }

    public func requestLocationPermissionIfNeeded() async -> Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                self.continuationLock.lock()
                self.authorizationContinuation = continuation
                self.continuationLock.unlock()
                self.locationManager.requestWhenInUseAuthorization()
            }
        @unknown default:
            return false
        }
    }

    public func currentSnapshot() async throws -> WeatherSnapshot {
        guard await requestLocationPermissionIfNeeded() else {
            throw AstraError(category: .auth, message: "Location access is off, so Kyra can't check today's weather. You can still plan outfits manually.")
        }

        let location = try await currentLocation()

        do {
            let weather = try await weatherKitService.weather(for: location)
            let today = weather.dailyForecast.forecast.first

            return WeatherSnapshot(
                temperatureHigh: today?.highTemperature.converted(to: .fahrenheit).value ?? weather.currentWeather.temperature.converted(to: .fahrenheit).value,
                temperatureLow: today?.lowTemperature.converted(to: .fahrenheit).value ?? weather.currentWeather.temperature.converted(to: .fahrenheit).value,
                apparentTemperature: weather.currentWeather.apparentTemperature.converted(to: .fahrenheit).value,
                condition: weather.currentWeather.condition.astraCondition,
                precipitationChance: today?.precipitationChance,
                windSpeed: weather.currentWeather.wind.speed.converted(to: .milesPerHour).value,
                humidity: weather.currentWeather.humidity,
                locationName: nil
            )
        } catch {
            throw AstraError.provider("Kyra couldn't check today's weather. Try again shortly.")
        }
    }

    private func currentLocation() async throws -> CLLocation {
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location {
                return location
            }
            if update.authorizationDenied || update.authorizationRestricted {
                throw AstraError.auth("Location access is off.")
            }
        }
        throw AstraError.network("Couldn't determine your location.")
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        continuationLock.lock()
        let continuation = authorizationContinuation
        authorizationContinuation = nil
        continuationLock.unlock()
        guard let continuation else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            continuation.resume(returning: true)
        default:
            continuation.resume(returning: false)
        }
    }
}

extension WeatherKit.WeatherCondition {
    fileprivate var astraCondition: AstraWeatherCondition {
        switch self {
        case .clear, .mostlyClear, .hot:
            .clear
        case .partlyCloudy:
            .partlyCloudy
        case .cloudy, .mostlyCloudy:
            .cloudy
        case .foggy, .haze, .smoky:
            .fog
        case .drizzle:
            .drizzle
        case .rain, .heavyRain, .isolatedThunderstorms:
            .rain
        case .thunderstorms, .strongStorms:
            .thunderstorm
        case .snow, .heavySnow, .flurries, .blizzard, .blowingSnow, .sleet, .wintryMix:
            .snow
        case .windy, .breezy:
            .windy
        default:
            .cloudy
        }
    }
}

/// Type alias to disambiguate our domain `WeatherCondition` from
/// `WeatherKit.WeatherCondition` within this file.
private typealias AstraWeatherCondition = AstraStyle.WeatherCondition
