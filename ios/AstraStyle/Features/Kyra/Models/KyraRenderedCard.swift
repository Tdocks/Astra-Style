//
//  KyraRenderedCard.swift
//  AstraStyle
//
//  What the conversation screen actually draws for each `KyraCard`.
//
//  A `KyraCard` is an ID reference, not a payload — `schema.ts` keeps the
//  wire shape to ids so the client renders from its own tables rather than
//  trusting a model-authored copy of a row it can look up itself. That
//  means every card needs a fetch before it can be drawn, and the fetch
//  can fail independently of the message it arrived in. This enum is the
//  post-fetch shape: either the joined, drawable model, or an honest
//  `.unavailable` naming what could not be loaded — never a
//  plausible-looking card invented from nothing.
//
//  There is deliberately no case for an unknown card TYPE and no renderer
//  fallback for one: `KyraCard`'s decoder throws on an unrecognized type
//  and the response decoder drops that entry before it reaches anything in
//  this feature (KyraResponse.swift documents the mechanism), so a
//  `default:` branch here would be code that cannot execute.
//

import Foundation

public enum KyraRenderedCard: Identifiable, Sendable {
    case outfit(KyraOutfitCardModel)
    case closetItem(KyraClosetItemCardModel)
    case product(KyraProductCardModel)
    case comparisonTable(id: UUID, table: ComparisonTable)
    case action(id: UUID, action: KyraSuggestedAction)
    case unavailable(KyraUnavailableCardModel)

    public var id: UUID {
        switch self {
        case .outfit(let model): model.id
        case .closetItem(let model): model.id
        case .product(let model): model.id
        case .comparisonTable(let id, _): id
        case .action(let id, _): id
        case .unavailable(let model): model.id
        }
    }
}

/// An outfit card joined to the rows that make it drawable: the `outfits`
/// row plus the hydrated garments (same `LookGarment` shape the Home hero
/// card and the Closet carousel draw — P5-KYRA-14's component-reuse
/// criterion starts with sharing the model those components consume).
public struct KyraOutfitCardModel: Identifiable, Sendable {
    /// The outfit's own id, which is what makes rehydration idempotent.
    public let id: UUID
    public var outfit: Outfit
    public var garments: [LookGarment]

    public init(outfit: Outfit, garments: [LookGarment]) {
        self.id = outfit.id
        self.outfit = outfit
        self.garments = garments
    }
}

public struct KyraClosetItemCardModel: Identifiable, Sendable {
    public let id: UUID
    public var item: ClosetItem
    public var imageURL: URL?

    public init(item: ClosetItem, imageURL: URL? = nil) {
        self.id = item.id
        self.item = item
        self.imageURL = imageURL
    }
}

/// A product card, rendered from the user's own evaluation of the
/// candidate (`POST /products/evaluate`) because that is the only product
/// read the client has: `KyraCard.product` carries just a
/// `product_candidate_id`, and `ShoppingRepository` has no fetch-by-id for
/// candidates — so brand/name/price/image are not renderable from this
/// card today. The evaluation's verdict and reasoning are real, useful,
/// and honestly what Kyra is pointing at when she cites a product.
public struct KyraProductCardModel: Identifiable, Sendable {
    public let id: UUID
    public var evaluation: ProductEvaluation

    public init(evaluation: ProductEvaluation) {
        self.id = evaluation.productCandidateID
        self.evaluation = evaluation
    }
}

/// A card whose referenced row could not be loaded. Says so, names the
/// kind, and offers retry only when retrying can succeed (spec §21) —
/// `isRetryable` mirrors `AstraError.isRetryable`, so a card that failed
/// because an endpoint is not built yet does not dangle a retry that can
/// never work.
public struct KyraUnavailableCardModel: Identifiable, Sendable {
    public let id: UUID
    public var summary: String
    public var isRetryable: Bool

    public init(id: UUID = UUID(), summary: String, isRetryable: Bool) {
        self.id = id
        self.summary = summary
        self.isRetryable = isRetryable
    }
}
