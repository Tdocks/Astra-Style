//
//  HomeWeekStripTests.swift
//  AstraStyleTests
//
//  Week-strip generate path, packing day decode, Add Occasion, Pack a trip.
//  Wear This stays on today; packing is the same scorer over a date range.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Week strip and packing")
struct HomeWeekStripTests {

    @Test("PackingDayPlan decodes a YYYY-MM-DD day, not an instant")
    func packingDayDecodesCalendarDate() throws {
        let json = """
        {
          "date": "2026-08-22",
          "outfit_id": "22222222-2222-4222-8222-222222222222",
          "is_rewear": true
        }
        """
        let day = try JSONDecoder().decode(PackingDayPlan.self, from: Data(json.utf8))
        let outfitID = try #require(UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        #expect(DateFormatter.astraDay.string(from: day.date) == "2026-08-22")
        #expect(day.isRewear)
        #expect(day.outfitID == outfitID)
    }

    @Test("Missing week days call packing once; a full week does not")
    func missingDaysGenerateThenIdempotent() async {
        let outfits = MockOutfitRepository()
        let provider = DefaultHomeBriefProvider(
            outfitRepository: outfits,
            profileRepository: MockProfileRepository(),
            closetRepository: MockClosetRepository(),
            weatherService: MockWeatherService(),
            imageURLResolver: WeekStripStubURLResolver()
        )

        let slots = await provider.loadWeekStrip()
        let looks = slots.filter { $0.hasLook }.count
        #expect(slots.count == 7)
        #expect(looks == 7)
        #expect(await outfits.packingGenerateCount == 1)

        let again = await provider.loadWeekStrip()
        #expect(again.count == 7)
        #expect(await outfits.packingGenerateCount == 1)
    }

    @Test("Home loads the week strip after today's brief")
    @MainActor
    func homeViewModelLoadsWeekSlots() async {
        let outfitID = UUID()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let slots = (0...6).compactMap { offset -> WeekDaySlot? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return WeekDaySlot(
                date: date,
                outfit: Outfit(id: outfitID, userID: SampleData.userID, name: "Look \(offset)"),
                occasionHeadline: offset == 2 ? "Dinner" : nil
            )
        }
        let provider = WeekStripHomeProvider(
            data: HomeBriefData(
                greetingName: "Marcus",
                weather: nil,
                schedule: nil,
                brief: DailyBrief(
                    id: UUID(),
                    userID: SampleData.userID,
                    briefDate: .now,
                    primaryOutfitID: outfitID
                ),
                primaryOutfit: Outfit(id: outfitID, userID: SampleData.userID, name: "Thursday"),
                primaryOutfitItems: [],
                closetRoleCounts: [.top: 2, .bottom: 2, .shoes: 1]
            ),
            slots: slots
        )
        let viewModel = HomeViewModel(
            provider: provider,
            networkMonitor: StaticNetworkReachabilityMonitor(offline: false)
        )

        await viewModel.onAppear()

        #expect(viewModel.weekSlots.count == 7)
        #expect(viewModel.weekSlots[2].occasionHeadline == "Dinner")
    }

    @Test("Saving an occasion writes the row and rebuilds the week")
    @MainActor
    func addOccasionSavesAndRegenerates() async {
        let outfits = MockOutfitRepository()
        let viewModel = AddOccasionViewModel(
            outfitRepository: outfits,
            currentUserID: { SampleData.userID }
        )
        viewModel.title = "  Client dinner  "
        viewModel.dressCode = .smartCasual

        #expect(await viewModel.save())

        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 8, to: start) ?? start
        let saved = (try? await outfits.fetchOccasions(from: start, to: end)) ?? []
        let savedDinner = saved.contains { $0.title == "Client dinner" && $0.dressCode == .smartCasual }
        #expect(savedDinner)
        #expect(await outfits.packingGenerateCount == 1)
    }

    @Test("Pack a trip stores the daily plan from the same generate path")
    @MainActor
    func packingTripGeneratesAPlan() async {
        let viewModel = PackingTripViewModel(
            outfitRepository: MockOutfitRepository(),
            closetRepository: MockClosetRepository()
        )
        viewModel.destination = "Lisbon"
        viewModel.hasLaundryAccess = true
        await viewModel.generate()

        #expect(viewModel.plan != nil)
        #expect((viewModel.plan?.dailyOutfitPlan.count ?? 0) >= 1)
        #expect(viewModel.error == nil)
        #expect(!viewModel.bagGarmentNames.isEmpty)
        let namesAreNotUUIDs = viewModel.bagGarmentNames.allSatisfy { name in
            UUID(uuidString: name) == nil
        }
        #expect(namesAreNotUUIDs)
    }

    @Test("Daily packing rows are identified by date so rewear does not collide")
    func packingDaysIdentifyByDateNotOutfit() throws {
        let outfitID = try #require(UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        let day1 = try #require(DateFormatter.astraDay.date(from: "2026-08-24"))
        let day2 = try #require(DateFormatter.astraDay.date(from: "2026-08-25"))
        let days = [
            PackingDayPlan(date: day1, outfitID: outfitID, isRewear: false),
            PackingDayPlan(date: day2, outfitID: outfitID, isRewear: true),
        ]
        let keys = days.map(\.dayKey)
        #expect(Set(keys).count == keys.count)
        #expect(Set(days.map(\.outfitID)).count == 1)
    }

    @Test("Packing trip modal has a stable identity")
    func packingTripModalIdentity() {
        #expect(AppModalRoute.packingTrip.id == "packingTrip")
        #expect(AppModalRoute.addOccasion.id == "addOccasion")
    }
}

private struct WeekStripStubURLResolver: ClosetImageURLResolving {
    func resolve(storagePath: String) async throws -> URL {
        throw AstraError.unimplemented("Week-strip tests never resolve a path")
    }
    func resolve(storagePaths: [String]) async throws -> [String: URL] { [:] }
}

private final class WeekStripHomeProvider: HomeBriefProviding, @unchecked Sendable {
    let data: HomeBriefData
    let slots: [WeekDaySlot]

    init(data: HomeBriefData, slots: [WeekDaySlot]) {
        self.data = data
        self.slots = slots
    }

    func loadTodayBrief(regenerate: Bool) async throws -> HomeBriefData { data }
    func markPrimaryOutfitWorn(_ data: HomeBriefData) async throws {}
    func weatherAuthorization() -> WeatherLocationAuthorization { .denied }
    func requestWeatherPermission() async -> Bool { false }
    func loadWeekStrip() async -> [WeekDaySlot] { slots }
}
