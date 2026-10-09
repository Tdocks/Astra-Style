import Foundation

/// A user's tracked purchase event. The candidate is kept as an ID so monthly
/// reporting can preserve the actual purchase timestamp without duplicating
/// catalog data.
public struct ProductPurchase: Codable, Hashable, Sendable {
    public let productCandidateID: UUID
    public let purchasedAt: Date

    public init(productCandidateID: UUID, purchasedAt: Date) {
        self.productCandidateID = productCandidateID
        self.purchasedAt = purchasedAt
    }
}
