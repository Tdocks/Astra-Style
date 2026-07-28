//
//  KyraResponse.swift
//  AstraStyle
//
//  Concrete Swift mirror of Kyra's structured response schema (spec §11):
//
//    {
//      "message": "string",
//      "intent": "daily_outfit | product_advice | outfit_review | packing | education | general",
//      "cards": [],
//      "suggested_actions": [],
//      "memory_proposals": [],
//      "confidence": 0.0
//    }
//
//  Kyra is required to return structured UI payloads rather than unparsed
//  prose (spec §31), so this type — not a raw string — is what
//  `KyraRepository.send(...)` returns and what `kyra_messages
//  .structured_payload` persists.
//

import Foundation

public struct KyraStructuredResponse: Codable, Hashable, Sendable {
    public var message: String
    public var intent: KyraIntent
    public var cards: [KyraCard]
    public var suggestedActions: [KyraSuggestedAction]
    public var memoryProposals: [KyraMemoryProposal]
    public var confidence: Double

    public init(
        message: String,
        intent: KyraIntent,
        cards: [KyraCard] = [],
        suggestedActions: [KyraSuggestedAction] = [],
        memoryProposals: [KyraMemoryProposal] = [],
        confidence: Double
    ) {
        self.message = message
        self.intent = intent
        self.cards = cards
        self.suggestedActions = suggestedActions
        self.memoryProposals = memoryProposals
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case message
        case intent
        case cards
        case suggestedActions = "suggested_actions"
        case memoryProposals = "memory_proposals"
        case confidence
    }
}

/// A structured card embedded in a Kyra response (spec §6.20 "Responses can
/// contain structured cards"). Modeled as an enum with associated payloads
/// so the UI layer can switch exhaustively rather than inspecting a
/// stringly-typed `type` field, while still round-tripping through the
/// server's `{"type": "...", ...}` JSON shape via custom `Codable`.
public enum KyraCard: Hashable, Sendable {
    case outfit(outfitID: UUID)
    case product(productCandidateID: UUID)
    case closetItem(closetItemID: UUID)
    case comparisonTable(ComparisonTable)
    case action(KyraSuggestedAction)
}

extension KyraCard: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case outfitID = "outfit_id"
        case productCandidateID = "product_candidate_id"
        case closetItemID = "closet_item_id"
        case table
        case action
    }

    private enum CardType: String, Codable {
        case outfit, product, closetItem = "closet_item", comparisonTable = "comparison_table", action
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(CardType.self, forKey: .type) {
        case .outfit:
            self = .outfit(outfitID: try container.decode(UUID.self, forKey: .outfitID))
        case .product:
            self = .product(productCandidateID: try container.decode(UUID.self, forKey: .productCandidateID))
        case .closetItem:
            self = .closetItem(closetItemID: try container.decode(UUID.self, forKey: .closetItemID))
        case .comparisonTable:
            self = .comparisonTable(try container.decode(ComparisonTable.self, forKey: .table))
        case .action:
            self = .action(try container.decode(KyraSuggestedAction.self, forKey: .action))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .outfit(let outfitID):
            try container.encode(CardType.outfit, forKey: .type)
            try container.encode(outfitID, forKey: .outfitID)
        case .product(let productCandidateID):
            try container.encode(CardType.product, forKey: .type)
            try container.encode(productCandidateID, forKey: .productCandidateID)
        case .closetItem(let closetItemID):
            try container.encode(CardType.closetItem, forKey: .type)
            try container.encode(closetItemID, forKey: .closetItemID)
        case .comparisonTable(let table):
            try container.encode(CardType.comparisonTable, forKey: .type)
            try container.encode(table, forKey: .table)
        case .action(let action):
            try container.encode(CardType.action, forKey: .type)
            try container.encode(action, forKey: .action)
        }
    }
}

public struct ComparisonTable: Codable, Hashable, Sendable {
    public var title: String
    public var columnHeaders: [String]
    public var rows: [[String]]

    public init(title: String, columnHeaders: [String], rows: [[String]]) {
        self.title = title
        self.columnHeaders = columnHeaders
        self.rows = rows
    }

    enum CodingKeys: String, CodingKey {
        case title
        case columnHeaders = "column_headers"
        case rows
    }
}

public struct KyraSuggestedAction: Codable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var kind: Kind

    public enum Kind: String, Codable, Sendable {
        case wearOutfit = "wear_outfit"
        case viewAlternatives = "view_alternatives"
        case openProduct = "open_product"
        case saveOutfit = "save_outfit"
        case scheduleOutfit = "schedule_outfit"
        case startStudioGeneration = "start_studio_generation"
        case addOccasion = "add_occasion"
    }

    public init(id: String, label: String, kind: Kind) {
        self.id = id
        self.label = label
        self.kind = kind
    }
}

/// A durable-memory candidate Kyra proposes saving (spec §6.20 "Conversation
/// memory: Save durable preferences only when relevant"). The user must
/// confirm before it's persisted as a `StyleMemory`.
public struct KyraMemoryProposal: Codable, Hashable, Sendable {
    public var memoryType: StyleMemoryType
    public var content: String
    public var confidence: Double

    public init(memoryType: StyleMemoryType, content: String, confidence: Double) {
        self.memoryType = memoryType
        self.content = content
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case memoryType = "memory_type"
        case content
        case confidence
    }
}
