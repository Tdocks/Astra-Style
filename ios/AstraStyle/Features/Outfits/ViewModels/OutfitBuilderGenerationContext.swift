import Foundation

public struct OutfitBuilderGenerationContext: Sendable {
    public let requestText: String
    public let weatherSnapshot: WeatherSnapshot?
}

public protocol OutfitBuilderGenerationContextProviding: Sendable {
    func makeContext() async throws -> OutfitBuilderGenerationContext
}

public struct EmptyOutfitContextProvider: OutfitBuilderGenerationContextProviding {
    public init() {}

    public func makeContext() async throws -> OutfitBuilderGenerationContext {
        OutfitBuilderGenerationContext(requestText: "", weatherSnapshot: nil)
    }
}

struct CurrentOutfitContextProvider: OutfitBuilderGenerationContextProviding {
    let profileRepository: ProfileRepository
    let weatherService: WeatherService
    let calendarService: CalendarService

    func makeContext() async throws -> OutfitBuilderGenerationContext {
        let profile = try await profileRepository.fetchCurrentProfile()
        let style = try await profileRepository.fetchStyleProfile()
        var weatherLine: String
        var weather: WeatherSnapshot?
        if weatherService.currentAuthorization() == .authorized,
           let reading = try? await weatherService.currentReading() {
            let snapshot = reading.snapshot
            weather = snapshot
            weatherLine =
                "\(reading.isLastKnown ? "Last-known weather" : "Weather"): \(snapshot.condition.rawValue), \(snapshot.temperatureLow)–\(snapshot.temperatureHigh) °F; " +
                    "precipitation probability \(snapshot.precipitationChance.map(String.init(describing:)) ?? "unknown"); " +
                    "season \(snapshot.season?.rawValue ?? "unknown")"
        } else {
            weatherLine = "Weather unavailable. Do not invent conditions."
        }

        var calendarLine: String
        if calendarService.currentAuthorization() == .authorized {
            let start = Calendar.current.startOfDay(for: .now)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
            let events = await calendarService.fetchUpcomingEvents(
                in: DateInterval(start: start, end: end),
                userID: profile.id
            )
            let schedule = events.map {
                "\($0.startsAt.formatted(date: .omitted, time: .shortened)): \($0.dressCode?.rawValue ?? "unspecified dress code")"
            }.joined(separator: "; ")
            calendarLine = "Today's calendar, times and dress codes only: \(schedule)"
        } else {
            calendarLine = "Calendar unavailable; use a versatile everyday look."
        }

        let styleSummary = style?.styleSummary ?? style?.primaryIdentity?.rawValue ?? "unspecified"
        let colors = style?.preferredColors.prefix(5).joined(separator: ", ") ?? "unspecified"
        let avoided = style?.avoidedColors.prefix(5).joined(separator: ", ") ?? "none"
        let fit = style?.preferredFit?.rawValue ?? "unspecified"
        let formality = style?.formalityPreference?.rawValue ?? "unspecified"
        let styleLine =
            "Wardrobe: \(profile.wardrobeGraph.rawValue); style: \(String(styleSummary.prefix(40))); " +
                "preferred colors: \(colors); avoid: \(avoided); fit: \(fit); formality: \(formality)."
        let lines = [
            "Create three different outfits using only my closet.",
            String(weatherLine.prefix(145)),
            String(calendarLine.prefix(145)),
            String(styleLine.prefix(145))
        ]

        return OutfitBuilderGenerationContext(
            requestText: String(lines.joined(separator: "\n").prefix(500)),
            weatherSnapshot: weather
        )
    }
}
