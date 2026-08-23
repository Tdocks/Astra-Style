//
//  ProductUnlock.swift
//  AstraStyle
//
//  Wire shape for `POST /products/unlocks`: a product this user already
//  evaluated, re-scored against this closet. Discover's Unlocks rail is
//  this list — not `product_candidates` ordered by `last_checked_at`.
//

import Foundation

public struct ProductUnlock: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID { candidate.id }
    public let candidate: ProductCandidate
    public let outfitsUnlocked: Int

    public init(candidate: ProductCandidate, outfitsUnlocked: Int) {
        self.candidate = candidate
        self.outfitsUnlocked = outfitsUnlocked
    }

    enum CodingKeys: String, CodingKey {
        case candidate
        case outfitsUnlocked = "outfits_unlocked"
    }
}

public struct ProductUnlockList: Codable, Sendable {
    public let items: [ProductUnlock]

    public init(items: [ProductUnlock]) {
        self.items = items
    }
}
