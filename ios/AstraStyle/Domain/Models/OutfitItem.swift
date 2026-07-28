//
//  OutfitItem.swift
//  AstraStyle
//
//  Maps `outfit_items` (spec §9). A row references either an owned closet
//  item or a not-yet-purchased product candidate ("Complete this look",
//  spec §6.12), never both.
//

import Foundation

public struct OutfitItem: Identifiable, Codable, Hashable, Sendable {
    /// `outfit_items` has no dedicated surrogate key in spec §9; the
    /// natural key is (outfit, sort_order). A stable synthetic `id` keeps
    /// the type usable in SwiftUI `List`/`ForEach` without relying on
    /// positional identity.
    public var id: UUID { UUID(astraDeterministicFrom: "\(outfitID)-\(sortOrder)") }

    public var outfitID: UUID
    public var closetItemID: UUID?
    public var productCandidateID: UUID?
    public var role: OutfitItemRole
    public var sortOrder: Int
    public var isRequired: Bool

    public init(
        outfitID: UUID,
        closetItemID: UUID? = nil,
        productCandidateID: UUID? = nil,
        role: OutfitItemRole,
        sortOrder: Int,
        isRequired: Bool = true
    ) {
        self.outfitID = outfitID
        self.closetItemID = closetItemID
        self.productCandidateID = productCandidateID
        self.role = role
        self.sortOrder = sortOrder
        self.isRequired = isRequired
    }

    enum CodingKeys: String, CodingKey {
        case outfitID = "outfit_id"
        case closetItemID = "closet_item_id"
        case productCandidateID = "product_candidate_id"
        case role
        case sortOrder = "sort_order"
        case isRequired = "is_required"
    }

    /// `true` when this slot references a garment the user doesn't yet
    /// own — i.e. it should render the "Complete this look" affordance.
    public var isMissingItem: Bool { closetItemID == nil && productCandidateID != nil }
}

extension UUID {
    /// A stable, deterministic UUID derived from a string seed using FNV-1a
    /// (not Swift's `Hasher`, which is randomly seeded per process and
    /// therefore *not* stable across launches). Used only to synthesize
    /// `Identifiable` keys for join-table rows with no surrogate primary
    /// key of their own — never persisted or sent to the server.
    init(astraDeterministicFrom seed: String) {
        // Two independent FNV-1a 64-bit digests (different offset basis)
        // concatenated to fill all 16 UUID bytes deterministically.
        func fnv1a64(_ input: String, offsetBasis: UInt64) -> UInt64 {
            var hash = offsetBasis
            let prime: UInt64 = 0x100000001b3
            for byte in input.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
            return hash
        }

        let high = fnv1a64(seed, offsetBasis: 0xcbf29ce484222325)
        let low = fnv1a64(seed, offsetBasis: 0x9e3779b97f4a7c15)

        let highBytes = withUnsafeBytes(of: high.bigEndian) { Array($0) }
        let lowBytes = withUnsafeBytes(of: low.bigEndian) { Array($0) }
        let uuidBytes = highBytes + lowBytes

        self = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }
}
