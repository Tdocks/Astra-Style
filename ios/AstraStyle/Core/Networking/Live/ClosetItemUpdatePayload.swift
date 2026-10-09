import Foundation

/// Encodes a full closet update while preserving SQL NULL for empty form fields.
/// Synthesized Optional encoding omits nil keys, which PostgREST interprets as
/// "leave unchanged" on PATCH. Explicit nulls let the form clear old metadata.
struct ClosetItemUpdatePayload: Encodable {
    let item: ClosetItem

    func encode(to encoder: Encoder) throws {
        try item.encode(to: encoder)
        var container = encoder.container(keyedBy: ClosetItem.CodingKeys.self)
        try container.encode(item.brand, forKey: .brand)
        try container.encode(item.subcategory, forKey: .subcategory)
        try container.encode(item.primaryColor, forKey: .primaryColor)
        try container.encode(item.pattern, forKey: .pattern)
        try container.encode(item.careInstructions, forKey: .careInstructions)
        try container.encode(item.size, forKey: .size)
        try container.encode(item.fit, forKey: .fit)
        try container.encode(item.condition, forKey: .condition)
        try container.encode(item.purchaseDate, forKey: .purchaseDate)
        try container.encode(item.pricePaid, forKey: .pricePaid)
        try container.encode(item.currency, forKey: .currency)
        try container.encode(item.retailer, forKey: .retailer)
        try container.encode(item.productURL, forKey: .productURL)
    }
}
