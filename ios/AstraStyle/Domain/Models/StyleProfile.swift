//
//  StyleProfile.swift
//  AstraStyle
//
//  Maps `style_profiles` (spec §9). Produced by Style DNA generation
//  (`POST /style-dna/generate`, spec §14) and editable from the Style DNA
//  result screen (spec §6.10).
//

import Foundation

public struct StyleProfile: Codable, Hashable, Sendable {
    public var userID: UUID
    public var primaryIdentity: StyleIdentity?
    public var secondaryIdentities: [StyleIdentity]

    /// The user's own stated goals from spec §6.4 ("Onboarding — Style goals"),
    /// e.g. "look sharper at work", "stop buying things I don't wear".
    ///
    /// Free text on purpose. These are the words the user chose, and Kyra's
    /// Style DNA summary should be able to echo them back rather than
    /// paraphrasing them into a taxonomy. `jsonb NOT NULL DEFAULT '[]'` in
    /// Postgres, so an empty array rather than nil is the "not answered" state.
    ///
    /// Missing from this model until the Phase 2 pre-flight, despite the column
    /// existing and §6.4 being a required onboarding step — the screen would
    /// have collected goals with nowhere to put them.
    public var styleGoals: [String]

    public var preferredColors: [String]
    public var avoidedColors: [String]
    public var preferredFit: ItemFit?
    public var formalityPreference: FormalityLevel?
    public var logoTolerance: ToleranceLevel?
    public var trendTolerance: ToleranceLevel?
    public var accessoryPreference: AccessoryPreference?
    public var styleSummary: String?

    /// pgvector embedding of the style summary, used server-side for
    /// similarity search. The client treats this as opaque and never
    /// computes with it directly.
    public var embedding: [Float]?

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        userID: UUID,
        primaryIdentity: StyleIdentity? = nil,
        secondaryIdentities: [StyleIdentity] = [],
        styleGoals: [String] = [],
        preferredColors: [String] = [],
        avoidedColors: [String] = [],
        preferredFit: ItemFit? = nil,
        formalityPreference: FormalityLevel? = nil,
        logoTolerance: ToleranceLevel? = nil,
        trendTolerance: ToleranceLevel? = nil,
        accessoryPreference: AccessoryPreference? = nil,
        styleSummary: String? = nil,
        embedding: [Float]? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.userID = userID
        self.primaryIdentity = primaryIdentity
        self.secondaryIdentities = secondaryIdentities
        self.styleGoals = styleGoals
        self.preferredColors = preferredColors
        self.avoidedColors = avoidedColors
        self.preferredFit = preferredFit
        self.formalityPreference = formalityPreference
        self.logoTolerance = logoTolerance
        self.trendTolerance = trendTolerance
        self.accessoryPreference = accessoryPreference
        self.styleSummary = styleSummary
        self.embedding = embedding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case primaryIdentity = "primary_identity"
        case secondaryIdentities = "secondary_identities"
        case styleGoals = "style_goals"
        case preferredColors = "preferred_colors"
        case avoidedColors = "avoided_colors"
        case preferredFit = "preferred_fit"
        case formalityPreference = "formality_preference"
        case logoTolerance = "logo_tolerance"
        case trendTolerance = "trend_tolerance"
        case accessoryPreference = "accessory_preference"
        case styleSummary = "style_summary"
        case embedding
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
