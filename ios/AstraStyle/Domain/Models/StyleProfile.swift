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

    /// 0–100, matching `style_profiles.logo_tolerance`, which is
    /// `smallint check (logo_tolerance between 0 and 100)`.
    ///
    /// Was `ToleranceLevel?` — a String-backed enum encoding `"low"` into a
    /// smallint column. Nothing caught it: `check_schema_drift.py` exempts
    /// `ToleranceLevel` precisely BECAUSE these columns are numeric, and
    /// `check_column_drift.py` compares key names rather than types, so the
    /// keys matched perfectly while the values could not have been stored. It
    /// had never fired only because both properties were nil everywhere in the
    /// app so far, and Swift's synthesised encoder omits a nil Optional — the
    /// first non-nil write would have failed at INSERT with `invalid input
    /// syntax for type smallint`, at runtime, on a user's onboarding
    /// submission.
    ///
    /// Use `ToleranceLevel`'s `score` / `init(score:)` bridge below to move
    /// between this and the low/medium/high vocabulary the UI speaks.
    public var logoTolerance: Int?

    /// 0–100, matching `style_profiles.trend_tolerance`. See `logoTolerance`.
    public var trendTolerance: Int?

    public var accessoryPreference: AccessoryPreference?
    public var styleSummary: String?

    /// The §6.9 preference quiz result — all eight dimensions with a confidence
    /// each. Written by onboarding, read by Style DNA generation.
    ///
    /// Not an Optional. `style_profiles.preference_vector` is
    /// `jsonb NOT NULL DEFAULT '{}'`, and an empty vector already means exactly
    /// what a nil one would: the quiz was skipped or produced nothing. Two ways
    /// to spell one state is how half the call sites end up handling only one
    /// of them.
    public var preferenceVector: StylePreferenceVector

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
        logoTolerance: Int? = nil,
        trendTolerance: Int? = nil,
        accessoryPreference: AccessoryPreference? = nil,
        styleSummary: String? = nil,
        preferenceVector: StylePreferenceVector = .skipped,
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
        self.preferenceVector = preferenceVector
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
        case preferenceVector = "preference_vector"
        case embedding
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - The low/medium/high vocabulary, over a 0–100 column

/// `logo_tolerance` and `trend_tolerance` are `smallint` 0–100 in Postgres, and
/// `ToleranceLevel` is the four-step vocabulary the UI and Kyra actually speak.
/// The mapping between them lives here and nowhere else, so a screen showing
/// "Medium" and a prompt saying "medium" cannot come to mean different numbers.
///
/// Declared in this file rather than in `Domain/Models/Enums.swift` on purpose:
/// `scripts/check_schema_drift.py` reads that file looking for enums that must
/// match a Postgres enum type, and `ToleranceLevel` is exempted there precisely
/// because these columns are numeric. Keeping the numeric bridge next to the
/// columns it serves puts it where someone editing those columns will see it.
public extension ToleranceLevel {

    /// The midpoint of this band, for writing to a 0–100 column.
    ///
    /// Midpoints rather than boundaries, so a value that round-trips through
    /// `init(score:)` comes back as the same band instead of landing on an edge
    /// and tipping into its neighbour.
    var score: Int {
        switch self {
        case .none: 0
        case .low: 25
        case .medium: 55
        case .high: 85
        }
    }

    /// The band a stored 0–100 score falls in. Values outside the range are
    /// clamped rather than rejected: this reads data, and refusing to display a
    /// profile because a number is out of bounds helps nobody.
    init(score: Int) {
        switch max(0, min(100, score)) {
        case 0..<10: self = .none
        case 10..<40: self = .low
        case 40..<70: self = .medium
        default: self = .high
        }
    }
}
