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
