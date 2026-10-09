import Foundation
import Testing
@testable import AstraStyle

@Suite("Item insights API contract")
struct ClosetItemInsightsTests {
    @Test("Insight endpoint uses GET and a lowercase owner item UUID")
    func endpoint() throws {
        let id = try #require(UUID(uuidString: "ABCDEF12-1111-4111-8111-111111111111"))
        let endpoint = AstraEndpoint.fetchItemInsights(id: id)
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "closet/items/abcdef12-1111-4111-8111-111111111111/insights")
    }

    @Test("Backend insight payload preserves missing inputs and referenced IDs")
    func decode() throws {
        let data = Data(#"""
        {"redundancyScore":82,
         "similarItems":[{"itemId":"11111111-1111-4111-8111-111111111111","similarity":82}],
         "pairings":[{"itemId":"22222222-2222-4222-8222-222222222222","score":71,"missingInputs":["weather"]}],
         "savedOutfitIds":[],"replacementReason":null,"missingRedundancyInputs":["fit"]}
        """#.utf8)
        let result = try JSONDecoder().decode(ClosetItemInsights.self, from: data)
        #expect(result.redundancyScore == 82)
        #expect(result.similarItems.first?.similarity == 82)
        #expect(result.pairings.first?.missingInputs == ["weather"])
        #expect(result.missingRedundancyInputs == ["fit"])
        #expect(result.replacementReason == nil)
    }
    @Test("Editing invalidates prior insights and refreshes recorded condition")
    @MainActor
    func editRefresh() async throws {
        var item = ClosetItem(id: UUID(), userID: UUID(), name: "Test shirt", category: .top, condition: .good)
        let repository = MockClosetRepository(items: [item])
        let model = ClosetItemDetailViewModel(itemID: item.id, closetRepository: repository,
                                              imageURLResolver: MockClosetImageURLResolver())
        await model.onAppear()
        #expect(model.insights?.replacementReason == nil)
        #expect(model.insights != nil)
        item.condition = .damaged
        let saved = try await repository.updateItem(item)
        model.applyEditedItem(saved)
        #expect(model.insights == nil)
        await model.loadInsights()
        #expect(model.insights?.replacementReason == "recorded_damage")
        #expect(model.insightItems[item.id]?.condition == .damaged)
        #expect(model.insightsError == nil)
    }

    @Test("Gallery loads actual saved look and keeps garments when photos cannot resolve")
    @MainActor
    func gallery() async throws {
        let id = try #require(SampleData.heroOutfitItems().first?.closetItemID)
        let model = ClosetItemDetailViewModel(itemID: id, closetRepository: MockClosetRepository(),
                                              imageURLResolver: MockClosetImageURLResolver(),
                                              outfitRepository: MockOutfitRepository())
        await model.onAppear()
        #expect(model.insightLooks.first?.outfit.name == SampleData.heroOutfit.name)
        #expect(model.insightLooks.first?.garments.contains { $0.item.id == id } == true)
        #expect(model.insightGalleryError == nil)
    }

}
