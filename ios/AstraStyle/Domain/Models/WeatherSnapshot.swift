//
//  WeatherSnapshot.swift
//  AstraStyle
//
//  A concretely-typed shape for the `weather_snapshot` jsonb payloads
//  stored on `outfit_wears` and `daily_briefs` (spec §9). Unlike the truly
//  open-ended jsonb columns (`analysis_metadata`, `prompt_payload`), the
//  weather shape is well-known — it is produced by our own Edge Functions
//  from a single weather provider integration — so it is worth modeling
//  concretely rather than leaving it as `AstraJSONValue`.
//

import Foundation

public struct WeatherSnapshot: Codable, Hashable, Sendable {
    public var temperatureHigh: Double
    public var temperatureLow: Double
    public var apparentTemperature: Double?
    public var condition: WeatherCondition
    public var precipitationChance: Double?
    public var windSpeed: Double?
    public var humidity: Double?
    public var locationName: String?

    public init(
        temperatureHigh: Double,
        temperatureLow: Double,
        apparentTemperature: Double? = nil,
        condition: WeatherCondition,
        precipitationChance: Double? = nil,
        windSpeed: Double? = nil,
        humidity: Double? = nil,
        locationName: String? = nil
    ) {
        self.temperatureHigh = temperatureHigh
        self.temperatureLow = temperatureLow
        self.apparentTemperature = apparentTemperature
        self.condition = condition
        self.precipitationChance = precipitationChance
        self.windSpeed = windSpeed
        self.humidity = humidity
        self.locationName = locationName
    }

    enum CodingKeys: String, CodingKey {
        case temperatureHigh = "temperature_high"
        case temperatureLow = "temperature_low"
        case apparentTemperature = "apparent_temperature"
        case condition
        case precipitationChance = "precipitation_chance"
        case windSpeed = "wind_speed"
        case humidity
        case locationName = "location_name"
    }
}

public enum WeatherCondition: String, Codable, Sendable {
    case clear
    case partlyCloudy = "partly_cloudy"
    case cloudy
    case fog
    case rain
    case drizzle
    case thunderstorm
    case snow
    case sleet
    case windy

    public var sfSymbolName: String {
        switch self {
        case .clear: "sun.max.fill"
        case .partlyCloudy: "cloud.sun.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .rain: "cloud.rain.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .snow: "snow"
        case .sleet: "cloud.sleet.fill"
        case .windy: "wind"
        }
    }
}

/// A concretely-typed shape for the `schedule_snapshot` jsonb payload on
/// `daily_briefs` — a compact summary of the day's calendar, not a full
/// `Occasion` list.
public struct ScheduleSnapshot: Codable, Hashable, Sendable {
    public var eventCount: Int
    public var earliestFormalityLevel: FormalityLevel?
    public var headline: String?

    public init(eventCount: Int, earliestFormalityLevel: FormalityLevel? = nil, headline: String? = nil) {
        self.eventCount = eventCount
        self.earliestFormalityLevel = earliestFormalityLevel
        self.headline = headline
    }

    enum CodingKeys: String, CodingKey {
        case eventCount = "event_count"
        case earliestFormalityLevel = "earliest_formality_level"
        case headline
    }
}
