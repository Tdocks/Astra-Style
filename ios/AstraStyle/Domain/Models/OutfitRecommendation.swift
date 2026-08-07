//
//  OutfitRecommendation.swift
//  AstraStyle
//
//  Matches spec §26 "Sample Domain Types" verbatim. This is the transient
//  ranked-outfit shape returned by `POST /outfits/generate` and
//  `POST /outfits/rank` (spec §14) — distinct from the persisted `Outfit`
//  entity: a recommendation becomes an `Outfit` (+ `OutfitItem` rows) only
//  once the user saves, schedules, or wears it (spec §5.4).
//

import Foundation

public struct OutfitRecommendation: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let reason: String
    public let compatibilityScore: Int
    public let itemIDs: [UUID]
    public let missingProductIDs: [UUID]

    /// The eight §10 components behind `compatibilityScore`.
    ///
    /// Additive to §26's shape rather than a change to it, and optional
    /// because the server may be asked for a score without its parts. When
    /// present it drives the §6.12 breakdown; when absent the screen shows the
    /// total alone.
    ///
    /// `frameHarmony` inside it is always nil from the server. Swift splits
    /// §10's single silhouette weight into garment-versus-garment and
    /// garment-versus-wearer (`docs/14-frame-fit.md`); only the first has a
    /// server implementation, and a nil there collapses the composite back to
    /// `silhouetteInternal` exactly as it did before frame fit existed.
    public let breakdown: CompatibilityBreakdown?

    /// Every input the score fell back to a documented prior for, in words.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// READ THIS BEFORE WRITING ANY COPY THAT DESCRIBES A RECOMMENDATION.
    ///
    /// The server's scorer has a prior for every missing input, and they are
    /// good priors: a man with no wear history, no location permission and a
    /// closet nobody has analysed still gets a sensible ranking on his first
    /// morning. That is the point of them.
    ///
    /// What they are not is evidence. A 0.6 colour prior is a defensible
    /// ranking input and an indefensible claim, and the distance between
    /// those two is one sentence on a card: "these colours work well
    /// together", about a garment nothing ever looked at.
    ///
    /// So every screen showing a reason MUST drop any sentence resting on an
    /// entry here. Empty means fully measured — and it genuinely can be
    /// empty, which is the only reason it is worth trusting when it is not.
    /// This is CLAUDE.md's governing rule at the one boundary where it would
    /// otherwise be unenforceable: past the network, a bare 74 is
    /// indistinguishable from a measured 74.
    /// ─────────────────────────────────────────────────────────────────────
    public let unmeasured: [String]

    /// The §3.1 register — what this outfit reads AS, 0–100.
    ///
    /// Distinct from formality *alignment* in the breakdown, which asks
    /// whether the garments agree. This one names the result: 30 is smart
    /// casual, 70 is business. Nil when nothing in the outfit could be scored.
    public let formalityRegister: Int?

    public init(
        id: UUID,
        name: String,
        reason: String,
        compatibilityScore: Int,
        itemIDs: [UUID],
        missingProductIDs: [UUID],
        breakdown: CompatibilityBreakdown? = nil,
        unmeasured: [String] = [],
        formalityRegister: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.reason = reason
        self.compatibilityScore = compatibilityScore
        self.itemIDs = itemIDs
        self.missingProductIDs = missingProductIDs
        self.breakdown = breakdown
        self.unmeasured = unmeasured
        self.formalityRegister = formalityRegister
    }

    /// Hand-written so a response from a server that predates these fields —
    /// or one that omits the breakdown by request — decodes rather than
    /// throwing. `unmeasured` defaults to empty, which is the *safe* default
    /// in one direction only: it claims nothing was degraded. That is correct
    /// solely because the server always sends the key; a synthesised absence
    /// would be the app quietly asserting confidence nobody gave it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        reason = try container.decode(String.self, forKey: .reason)
        compatibilityScore = try container.decode(Int.self, forKey: .compatibilityScore)
        itemIDs = try container.decode([UUID].self, forKey: .itemIDs)
        missingProductIDs = try container.decodeIfPresent([UUID].self, forKey: .missingProductIDs) ?? []
        breakdown = try container.decodeIfPresent(CompatibilityBreakdown.self, forKey: .breakdown)
        unmeasured = try container.decodeIfPresent([String].self, forKey: .unmeasured) ?? []
        formalityRegister = try container.decodeIfPresent(Int.self, forKey: .formalityRegister)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case reason
        case compatibilityScore = "compatibility_score"
        case itemIDs = "item_ids"
        case missingProductIDs = "missing_product_ids"
        case breakdown
        case unmeasured
        case formalityRegister = "formality_register"
    }
}

public extension OutfitRecommendation {
    /// Whether any sentence about this recommendation can safely describe
    /// *why* it was chosen, or only *that* it was.
    ///
    /// A convenience with one job: making the rule in `unmeasured` cheap
    /// enough to obey that nobody is tempted to skip it.
    var isFullyMeasured: Bool { unmeasured.isEmpty }
}
