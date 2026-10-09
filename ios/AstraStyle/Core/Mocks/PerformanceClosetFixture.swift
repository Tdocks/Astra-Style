//
//  PerformanceClosetFixture.swift
//  AstraStyle
//
//  Deterministic, local-only data for the opt-in closet scrolling measurement.
//

import Foundation

enum PerformanceClosetFixture {
    static let itemCount = 125

    static let items: [ClosetItem] = (0..<itemCount).compactMap(makeItem(at:))

    private static func makeItem(at index: Int) -> ClosetItem? {
        guard !SampleData.closetItems.isEmpty else { return nil }
        let source = SampleData.closetItems[index % SampleData.closetItems.count]
        let suffix = String(format: "%012llx", UInt64(index + 1))
        guard let id = UUID(uuidString: "00000000-0000-4000-8000-\(suffix)") else { return nil }
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))

        return ClosetItem(
            id: id,
            userID: source.userID,
            name: "\(source.name) \(index + 1)",
            brand: source.brand,
            category: source.category,
            subcategory: source.subcategory,
            primaryColor: source.primaryColor,
            secondaryColors: source.secondaryColors,
            pattern: source.pattern,
            material: source.material,
            size: source.size,
            fit: source.fit,
            condition: source.condition,
            seasonality: source.seasonality,
            formalityScore: source.formalityScore,
            warmthScore: source.warmthScore,
            waterResistanceScore: source.waterResistanceScore,
            purchaseDate: source.purchaseDate,
            pricePaid: source.pricePaid,
            currency: source.currency,
            retailer: source.retailer,
            productURL: source.productURL,
            wearCount: source.wearCount,
            lastWornAt: source.lastWornAt,
            laundryState: source.laundryState,
            availabilityState: source.availabilityState,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
