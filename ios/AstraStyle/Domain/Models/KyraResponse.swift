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

    // MARK: - Defensive decoding (P5-CORE-01)
    //
    // Synthesized `Codable` throws the ENTIRE response away for any single
    // deviation from the schema above — an `intent` the client predates, one
    // bad card in an otherwise-good list, a provider that omits an empty
    // `suggested_actions` instead of sending `[]`. Kyra's Edge Function
    // (`supabase/functions/kyra/schema.ts`) already treats those as two
    // different classes of failure: a malformed TOP-LEVEL shape (not an
    // object, `message`/`intent`/`confidence` missing or mistyped) fails the
    // whole turn, but a bad card, action, or memory proposal is dropped and
    // the rest of the response ships — "failing a whole good answer over one
    // malformed card punishes the user for a defect the response survives
    // without" (schema.ts). This decoder mirrors that split, so a client
    // one release behind the server degrades instead of showing an error
    // where the server would have shown Kyra's actual message.
    //
    // `intent` is decoded as a bare `String` first and mapped, rather than
    // decoding straight to `KyraIntent` and catching the throw: `KyraIntent`
    // (Domain/Models/Enums.swift) is out of this ticket's scope and shared
    // by `AnalyticsEvent`, so it stays a plain raw-value enum. Mapping the
    // fallback here gets the `.general` degrade without teaching every other
    // reader of `KyraIntent` to tolerate a phantom "unknown" case.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)

        let rawIntent = try container.decode(String.self, forKey: .intent)
        intent = KyraIntent(rawValue: rawIntent) ?? .general

        cards = try Self.decodingDroppingInvalidEntries(KyraCard.self, forKey: .cards, from: container)
        suggestedActions = try Self.decodingDroppingInvalidEntries(
            KyraSuggestedAction.self,
            forKey: .suggestedActions,
            from: container
        )
        memoryProposals = try Self.decodingDroppingInvalidEntries(
            KyraMemoryProposal.self,
            forKey: .memoryProposals,
            from: container
        )

        // Clamped, not trusted: the model self-reports this number (spec
        // §11), and a provider hiccup that emits e.g. 42 instead of 0.42
        // should not propagate a confidence reading no UI treatment expects
        // (hedged-language correlation below 0.5, spec §11) or that the
        // server itself would ever send — `schema.ts`'s own parser clamps
        // this exact field the same way.
        let rawConfidence = try container.decode(Double.self, forKey: .confidence)
        confidence = min(1, max(0, rawConfidence))
    }

    /// Decodes `key` as an array of `T`, dropping entries that fail to
    /// decode as `T` instead of failing the whole array.
    ///
    /// The obvious approach — `while !nested.isAtEnd { try? nested.decode(T.self) }`
    /// — doesn't work: `UnkeyedDecodingContainer.decode(_:)` only advances
    /// its cursor on SUCCESS, so a `try?` that swallows a thrown error
    /// leaves the cursor pointing at the same malformed element forever and
    /// the loop never terminates. Decoding each element as `AstraJSONValue`
    /// first sidesteps that: its decoder accepts any valid JSON value, so it
    /// always advances the cursor, and re-encoding that value to `Data` and
    /// decoding `T` from it as a second, independent pass is what actually
    /// gets to drop just the one bad element rather than the whole array.
    ///
    /// A missing or `null` key decodes to `[]` rather than throwing, so an
    /// omitted optional collection (`suggested_actions` in particular —
    /// P5-CORE-01's acceptance criteria) parses successfully even though
    /// today's schema always sends it.
    private static func decodingDroppingInvalidEntries<T: Decodable>(
        _ type: T.Type,
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [T] {
        guard let rawEntries = try container.decodeIfPresent([AstraJSONValue].self, forKey: key) else {
            return []
        }
        let entryEncoder = JSONEncoder()
        let entryDecoder = JSONDecoder()
        return rawEntries.compactMap { entry in
            guard let data = try? entryEncoder.encode(entry) else { return nil }
            return try? entryDecoder.decode(T.self, from: data)
        }
    }
}

/// A structured card embedded in a Kyra response (spec §6.20 "Responses can
/// contain structured cards"). Modeled as an enum with associated payloads
/// so the UI layer can switch exhaustively rather than inspecting a
/// stringly-typed `type` field, while still round-tripping through the
/// server's `{"type": "...", ...}` JSON shape via custom `Codable`.
///
/// NOT a lossless mirror of the wire shape, and deliberately so:
/// `schema.ts`'s `.outfit` card carries additive `reason`,
/// `compatibility_score`, and `item_ids` fields ("additive beyond the Swift
/// decode shape; Codable ignores them" — that file's own comment). Nothing
/// here reads them, so decode → re-encode of an outfit card drops them; if
/// a future screen needs the reason text or score, it has to be added as a
/// stored property and a `CodingKeys` entry here, not assumed to already
/// survive the round trip.
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

    /// Deliberately still throws on an unrecognized `CardType` rather than,
    /// say, adding an `.unrecognized(String)` case: `KyraStructuredResponse
    /// .init(from:)` is the only place `[KyraCard]` is ever decoded, and it
    /// relies on exactly this throw to know which array entries to drop
    /// (`decodingDroppingInvalidEntries`). A card type this initializer
    /// swallowed quietly would have nowhere honest to go — it isn't one of
    /// the five renderable shapes below — so it must never become a
    /// plausible-looking card of a type we DO understand. Absent is honest;
    /// a confounded reading is not.
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

    /// Kept a plain raw-value enum, same reasoning as `KyraCard.CardType`:
    /// its synthesized decoder throwing on an unrecognized `kind` string is
    /// exactly what lets `KyraStructuredResponse.init(from:)` drop just that
    /// one action (whether standalone in `suggested_actions` or nested in a
    /// `KyraCard.action`) rather than guessing it into one of the seven
    /// kinds below.
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
///
/// An unrecognized `memory_type` throws here for the same reason
/// `KyraCard.CardType` does, and gets the same treatment: dropped by
/// `KyraStructuredResponse.init(from:)`, not guessed into an existing
/// `StyleMemoryType`. `confidence` is deliberately NOT clamped the way
/// `KyraStructuredResponse.confidence` is — `schema.ts`'s own
/// `parseMemoryProposal` drops a proposal whose confidence falls outside
/// 0...1 rather than clamping it, because a memory proposal is a claim
/// about to be shown to the user for confirmation ("Kyra thinks you dislike
/// X — save this?"); clamping a garbled confidence into range would still
/// present the claim as trustworthy, where dropping it is honest about not
/// knowing how much to trust it.
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

    /// The custom initializer this type needs is narrower than
    /// `KyraStructuredResponse`'s: `memoryType` already throws on an
    /// unrecognized value via synthesis (nothing to add), and `content`
    /// needs no defensive handling. Only `confidence` needs a check, and it
    /// needs to THROW rather than clamp — see the type doc comment above
    /// for why — which synthesized `Codable` cannot express either way.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        memoryType = try container.decode(StyleMemoryType.self, forKey: .memoryType)
        content = try container.decode(String.self, forKey: .content)
        let rawConfidence = try container.decode(Double.self, forKey: .confidence)
        guard (0...1).contains(rawConfidence) else {
            throw DecodingError.dataCorruptedError(
                forKey: .confidence,
                in: container,
                debugDescription: "memory_proposals[].confidence must be within 0...1; got \(rawConfidence)."
            )
        }
        confidence = rawConfidence
    }
}
