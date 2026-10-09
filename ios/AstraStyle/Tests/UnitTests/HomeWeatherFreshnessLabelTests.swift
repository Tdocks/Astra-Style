import Foundation
import Testing
@testable import AstraStyle

@Suite("Home weather observation freshness")
struct HomeWeatherFreshnessLabelTests {
    @Test("Last-known weather has a visible saved-observation label")
    func cachedWeatherIsMarkedForPresentation() {
        var data = makeBrief(weatherIsLastKnown: true)
        data.weather?.observedAt = .now.addingTimeInterval(-10 * 60)
        #expect(data.shouldLabelWeatherObservation)
        #expect(data.weatherIsLastKnown)
    }

    @Test("Old persisted observations are labeled even without cache-source metadata")
    func oldPersistedWeatherIsMarkedForPresentation() {
        var data = makeBrief(weatherIsLastKnown: false)
        data.weather?.observedAt = .now.addingTimeInterval(-3 * 60 * 60)
        #expect(data.shouldLabelWeatherObservation)
    }

    @Test("Fresh observation needs no extra stale label")
    func freshWeatherIsNotMarked() {
        let data = makeBrief(weatherIsLastKnown: false)
        #expect(!data.shouldLabelWeatherObservation)
    }

    private func makeBrief(weatherIsLastKnown: Bool) -> HomeBriefData {
        HomeBriefData(
            greetingName: "A",
            weather: WeatherSnapshot(
                temperatureHigh: 70,
                temperatureLow: 55,
                condition: .clear,
                observedAt: .now
            ),
            schedule: nil,
            weatherIsLastKnown: weatherIsLastKnown,
            brief: DailyBrief(id: UUID(), userID: UUID(), briefDate: .now),
            primaryOutfit: nil,
            primaryOutfitItems: []
        )
    }
}
