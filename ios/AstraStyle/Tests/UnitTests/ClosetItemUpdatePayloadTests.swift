import Foundation
import Testing
@testable import AstraStyle

@Suite("Closet update payload")
struct ClosetItemUpdatePayloadTests {
    @Test("Nil editable fields encode explicit null and immutable fields stay present")
    func nilMetadataCanBeCleared() throws {
        let id = UUID()
        let owner = UUID()
        let item = ClosetItem(
            id: id,
            userID: owner,
            name: "Navy coat",
            category: .outerwear,
            formalityScore: 82,
            warmthScore: 91,
            waterResistanceScore: 44,
            wearCount: 17
        )

        let data = try JSONEncoder.astraDefault.encode(ClosetItemUpdatePayload(item: item))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["id"] as? String)?.lowercased() == id.uuidString.lowercased())
        #expect((object["user_id"] as? String)?.lowercased() == owner.uuidString.lowercased())
        #expect(object["wear_count"] as? Int == 17)
        #expect(object["formality_score"] as? Int == 82)
        #expect(object["warmth_score"] as? Int == 91)
        #expect(object["water_resistance_score"] as? Int == 44)
        for key in ["brand", "care_instructions", "size", "subcategory", "primary_color", "pattern", "fit", "condition", "purchase_date", "price_paid", "retailer", "product_url"] {
            #expect(object.keys.contains(key))
            #expect(object[key] is NSNull)
        }
    }

    @Test("Legacy server rows with omitted optional metadata still decode")
    func omittedOptionalFieldsDecodeAsNil() throws {
        let item = ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: "Legacy shirt",
            category: .top,
            wearCount: 3
        )
        let complete = try JSONEncoder.astraDefault.encode(item)
        var object = try #require(JSONSerialization.jsonObject(with: complete) as? [String: Any])
        object.removeValue(forKey: "brand")
        object.removeValue(forKey: "care_instructions")
        object.removeValue(forKey: "size")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder.astraDefault.decode(ClosetItem.self, from: legacyData)
        #expect(decoded.id == item.id)
        #expect(decoded.userID == item.userID)
        #expect(decoded.wearCount == 3)
        #expect(decoded.brand == nil)
        #expect(decoded.careInstructions == nil)
        #expect(decoded.size == nil)
    }
}
