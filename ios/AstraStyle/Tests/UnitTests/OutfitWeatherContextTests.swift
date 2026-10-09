import Foundation
import Testing
@testable import AstraStyle

@Suite("Outfit generation weather context")
struct OutfitWeatherContextTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A fresh snapshot encodes only the backend weather context contract")
    func freshWeatherEncodes() throws {
        let snapshot = WeatherSnapshot(
            temperatureHigh: 72,
            temperatureLow: 54,
            condition: .rain,
            precipitationChance: 0.7,
            season: .fall,
            observedAt: now.addingTimeInterval(-60),
            temperatureCelsius: 18.5
        )
        let object = try encodedObject(OutfitGenerationRequest(weatherSnapshot: snapshot))
        let context = try #require(object["weather_context"] as? [String: Any])

        #expect(context["temperature_celsius"] as? Double == 18.5)
        #expect(context["precipitation_chance"] as? Double == 0.7)
        #expect(context["season"] as? String == "fall")
        let observedAt = try #require(snapshot.observedAt)
        #expect(context["observed_at"] as? String == ISO8601DateFormatter().string(from: observedAt))
        #expect(context["location_name"] == nil)
        #expect(context["latitude"] == nil)
        #expect(context["longitude"] == nil)
    }

    @Test("Legacy, incomplete, stale, and too-far-future snapshots omit weather context")
    func unavailableWeatherOmitsContext() throws {
        let old = WeatherSnapshot(temperatureHigh: 70, temperatureLow: 50, condition: .clear)
        let missingTemperature = WeatherSnapshot(
            temperatureHigh: 70, temperatureLow: 50, condition: .clear,
            precipitationChance: 0.2, observedAt: now, temperatureCelsius: nil
        )
        let stale = snapshot(observedAt: now.addingTimeInterval(-7_201))
        let tooFarFuture = snapshot(observedAt: now.addingTimeInterval(301))

        for weather in [old, missingTemperature, stale, tooFarFuture] {
            #expect(try encodedObject(OutfitGenerationRequest(weatherSnapshot: weather))["weather_context"] == nil)
        }
        #expect(try encodedObject(OutfitGenerationRequest())["weather_context"] == nil)
    }

    @Test("Older stored snapshots decode without provider metadata")
    func olderSnapshotDecodes() throws {
        let data = Data(#"{"temperature_high":72,"temperature_low":54,"condition":"clear"}"#.utf8)
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: data)
        #expect(decoded.observedAt == nil)
        #expect(decoded.temperatureCelsius == nil)
    }

    @Test("The accepted age and clock-skew boundaries remain valid")
    func freshnessBoundaries() throws {
        for instant in [now.addingTimeInterval(-7_200), now.addingTimeInterval(300)] {
            let context = try encodedObject(OutfitGenerationRequest(weatherSnapshot: snapshot(observedAt: instant)))
            #expect(context["weather_context"] != nil)
        }
    }

    private func snapshot(observedAt: Date) -> WeatherSnapshot {
        WeatherSnapshot(
            temperatureHigh: 70, temperatureLow: 50, condition: .clear,
            precipitationChance: 0.2, observedAt: observedAt, temperatureCelsius: 10
        )
    }

    private func encodedObject(_ request: OutfitGenerationRequest) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(GenerateOutfitsBody(request, now: now))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
