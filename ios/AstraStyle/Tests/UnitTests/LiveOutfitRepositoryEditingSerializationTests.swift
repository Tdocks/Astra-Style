import Foundation
import Testing
@testable import AstraStyle

@Suite("Outfit edit RPC serialization")
struct OutfitEditWireTests {
    @Test("RPC payload uses exact argument names and ordered owned item roles")
    func encodesExactReplaceRPCContract() throws {
        let outfitID = try #require(UUID(uuidString: "D3400000-0000-4000-8000-000000000031"))
        let firstID = try #require(UUID(uuidString: "D3400000-0000-4000-8000-000000000011"))
        let secondID = try #require(UUID(uuidString: "D3400000-0000-4000-8000-000000000012"))
        let expectedAt = Date(timeIntervalSince1970: 1_791_522_000)
        let payload = OutfitItemsReplaceParameters(
            outfitID: outfitID,
            expectedUpdatedAt: expectedAt,
            name: "Edited look",
            description: "Keeps the knit top.",
            compatibilityScore: 84,
            items: [
                OutfitItemsReplaceItem(closetItemID: firstID, role: "top", sortOrder: 0),
                OutfitItemsReplaceItem(closetItemID: secondID, role: "bottom", sortOrder: 1)
            ]
        )
        let encoded = try JSONEncoder().encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == Set([
            "p_outfit_id", "p_expected_updated_at", "p_name", "p_description",
            "p_compatibility_score", "p_items"
        ]))
        #expect((object["p_outfit_id"] as? String)?.lowercased() == outfitID.uuidString.lowercased())
        #expect(object["p_name"] as? String == "Edited look")
        #expect(object["p_description"] as? String == "Keeps the knit top.")
        #expect(object["p_compatibility_score"] as? Int == 84)
        let items = try #require(object["p_items"] as? [[String: Any]])
        #expect(items.count == 2)
        #expect((items[0]["closet_item_id"] as? String)?.lowercased() == firstID.uuidString.lowercased())
        #expect(items[0]["role"] as? String == "top")
        #expect(items[0]["sort_order"] as? Int == 0)
        #expect((items[1]["closet_item_id"] as? String)?.lowercased() == secondID.uuidString.lowercased())
        #expect(items[1]["role"] as? String == "bottom")
        #expect(items[1]["sort_order"] as? Int == 1)
    }
}
