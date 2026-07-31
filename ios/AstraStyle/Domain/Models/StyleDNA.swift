//
//  StyleDNA.swift
//  AstraStyle
//
//  The result of `POST /style-dna/generate` (spec §14), which is exactly what
//  the Style DNA result screen (spec §6.10) renders.
//
//  WHY THIS TYPE EXISTS RATHER THAN REUSING `StyleProfile`.
//
//  `generateStyleDNA()` used to return `StyleProfile`, and `StyleProfile` is a
//  row in `style_profiles`. Three of §6.10's six sections have no column
//  there and never will: "best silhouette direction", "signature item
//  opportunities" and "initial wardrobe priorities" are generated prose about
//  a wardrobe, not attributes of one. Returning the row meant the result
//  screen could show half of what §6.10 lists and no more, with no compiler
//  error and no test failure to say so — the screen just would not have had
//  the data.
//
//  So the endpoint returns this, and the four columns it DOES own
//  (formality/logo/trend/accessory) are on it too, mirrored from the row it
//  wrote. §6.10's "allow user to edit and regenerate" still works through
//  `ProfileRepository.updateStyleProfile` — the edit writes the row, then a
//  regenerate reads it back — so there is one write path for the user's own
//  answers, not two that can disagree.
//
//  NOTE ON `StylistReasoningProvider`. Spec §8 names five provider protocols
//  and this type is the output of one of them, but there is deliberately no
//  Swift `StylistReasoningProvider`. ADR 0004's decision 3 is that the client
//  never constructs a request to a model vendor; a client-side protocol for
//  doing so would be a seam for something the app is structurally forbidden
//  from doing. The protocol lives in
//  `supabase/functions/_shared/providers/stylistReasoning.ts`, and the client's
//  seam for the same capability is `ProfileRepository` — protocol on the
//  client, mock in `Core/Mocks`, live implementation over `AstraAPIClient`.
//
//  EVERY FIELD IS DECODED DEFENSIVELY except the six §6.10 sections. A Style
//  DNA that fails to decode because the server added a field is a blank
//  result screen for every user on the older build, and this response is
//  generated prose whose shape will keep growing.
//

import Foundation

// MARK: - Sections

/// One named recommendation — a signature piece, or a wardrobe priority.
///
/// `reason` is not optional and not decoration. §6.10's screen shows *why*
/// alongside *what*, and a recommendation with no reason is the "generic
/// output" failure `docs/11-risk-register.md` tracks: it reads as advice
/// while being a list.
public struct StyleDNARecommendation: Codable, Hashable, Sendable, Identifiable {
    public var title: String
    public var reason: String

    /// Stable within one result, because the title is what the screen keys on
    /// and two recommendations never share one.
    public var id: String { title }

    public init(title: String, reason: String) {
        self.title = title
        self.reason = reason
    }
}

/// A wardrobe priority, in the order the generator ranked them.
///
/// `rank` is carried rather than inferred from array position so a screen
/// that filters or reorders (a "show me the top two" affordance, a
/// server-side reorder) still displays the number the generator meant.
public struct StyleDNAPriority: Codable, Hashable, Sendable, Identifiable {
    public var rank: Int
    public var title: String
    public var reason: String

    public var id: String { "\(rank)-\(title)" }

    public init(rank: Int, title: String, reason: String) {
        self.rank = rank
        self.title = title
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case rank, title, reason
    }
}

/// §6.10's "Preferred palette".
public struct StyleDNAPalette: Codable, Hashable, Sendable {
    public var preferredColors: [String]
    public var avoidedColors: [String]
    /// One sentence on why this palette and not a neighbouring one.
    public var rationale: String

    public init(preferredColors: [String] = [], avoidedColors: [String] = [], rationale: String = "") {
        self.preferredColors = preferredColors
        self.avoidedColors = avoidedColors
        self.rationale = rationale
    }

    enum CodingKeys: String, CodingKey {
        case preferredColors = "preferred_colors"
        case avoidedColors = "avoided_colors"
        case rationale
    }
}

/// §6.10's "Best silhouette direction".
public struct StyleDNASilhouette: Codable, Hashable, Sendable {
    /// One line, shown large.
    public var headline: String
    /// The paragraph under it. Always about what the garment does, never
    /// about the wearer's body (spec §2, `docs/14-frame-fit.md` §4).
    public var detail: String

    public init(headline: String = "", detail: String = "") {
        self.headline = headline
        self.detail = detail
    }
}

// MARK: - The result

public struct StyleDNA: Codable, Hashable, Sendable {

    // §6.10 "Primary style identity". Optional because a profile with no
    // identity and no dress code has none, and the server returns null
    // rather than inventing one — see the Edge Function's own header. The
    // screen must render that state rather than assuming a value.
    public var primaryIdentity: StyleIdentity?

    /// Which input produced the identity, in the user's own terms.
    ///
    /// Present so the screen can distinguish "you told us this" from "we
    /// inferred this from your dress code" without the two reading
    /// identically. Showing an inferred identity in the same voice as a
    /// chosen one is how a guess becomes a fact the user never checked.
    public var identityBasis: String

    /// §6.10 "Secondary influences".
    public var secondaryInfluences: [StyleIdentity]

    /// §6.10 "Preferred palette".
    public var palette: StyleDNAPalette

    /// §6.10 "Best silhouette direction".
    public var silhouette: StyleDNASilhouette

    /// §6.10 "Signature item opportunities".
    public var signatureOpportunities: [StyleDNARecommendation]

    /// §6.10 "Initial wardrobe priorities".
    public var wardrobePriorities: [StyleDNAPriority]

    /// The written summary, also stored as `style_profiles.style_summary`.
    public var summary: String

    // The four `style_profiles` columns this endpoint owns — the generator's
    // considered read across goals, identity, lifestyle and the §6.9 vector,
    // NOT the quiz's raw output. See
    // supabase/migrations/20260730180000_style_preference_vector.sql.
    public var formalityPreference: FormalityLevel?
    /// 0–100, matching the smallint column. Use `ToleranceLevel(score:)` for
    /// the low/medium/high vocabulary the UI speaks.
    public var logoTolerance: Int?
    /// 0–100. See `logoTolerance`.
    public var trendTolerance: Int?
    public var accessoryPreference: AccessoryPreference?

    /// What the result was actually built from, in plain words.
    ///
    /// The honest half of the contract. Sparse input is the normal case —
    /// two §6.9 dimensions still rest on a single comparison — and a
    /// result that does not say what it knew is indistinguishable from one
    /// built from everything. That indistinguishability is how a thin Style
    /// DNA ships looking complete.
    public var knownInputs: [String]

    /// What would sharpen it, each phrased as what answering would change.
    public var openQuestions: [String]

    /// The §6.9 axes that produced a score, as raw `StyleDimension` values.
    ///
    /// Kept as strings rather than `[StyleDimension]` so an axis the server
    /// adds before this build knows about it is still displayable rather than
    /// dropped — same forward-compatibility rule as
    /// `StylePreferenceVector.init(from:)`.
    public var measuredDimensions: [String]

    public var generatedAt: Date

    /// The exact model/version behind this result, stored for attribution.
    ///
    /// The client never branches on it — that would be a vendor dependency in
    /// the app, which ADR 0004 exists to prevent. It is displayed only in
    /// diagnostic contexts and logged with feedback.
    public var modelIdentifier: String

    public init(
        primaryIdentity: StyleIdentity? = nil,
        identityBasis: String = "",
        secondaryInfluences: [StyleIdentity] = [],
        palette: StyleDNAPalette = StyleDNAPalette(),
        silhouette: StyleDNASilhouette = StyleDNASilhouette(),
        signatureOpportunities: [StyleDNARecommendation] = [],
        wardrobePriorities: [StyleDNAPriority] = [],
        summary: String = "",
        formalityPreference: FormalityLevel? = nil,
        logoTolerance: Int? = nil,
        trendTolerance: Int? = nil,
        accessoryPreference: AccessoryPreference? = nil,
        knownInputs: [String] = [],
        openQuestions: [String] = [],
        measuredDimensions: [String] = [],
        generatedAt: Date = .now,
        modelIdentifier: String = ""
    ) {
        self.primaryIdentity = primaryIdentity
        self.identityBasis = identityBasis
        self.secondaryInfluences = secondaryInfluences
        self.palette = palette
        self.silhouette = silhouette
        self.signatureOpportunities = signatureOpportunities
        self.wardrobePriorities = wardrobePriorities
        self.summary = summary
        self.formalityPreference = formalityPreference
        self.logoTolerance = logoTolerance
        self.trendTolerance = trendTolerance
        self.accessoryPreference = accessoryPreference
        self.knownInputs = knownInputs
        self.openQuestions = openQuestions
        self.measuredDimensions = measuredDimensions
        self.generatedAt = generatedAt
        self.modelIdentifier = modelIdentifier
    }

    enum CodingKeys: String, CodingKey {
        case primaryIdentity = "primary_identity"
        case identityBasis = "identity_basis"
        case secondaryInfluences = "secondary_influences"
        case palette
        case silhouette
        case signatureOpportunities = "signature_opportunities"
        case wardrobePriorities = "wardrobe_priorities"
        case summary
        case formalityPreference = "formality_preference"
        case logoTolerance = "logo_tolerance"
        case trendTolerance = "trend_tolerance"
        case accessoryPreference = "accessory_preference"
        case knownInputs = "known_inputs"
        case openQuestions = "open_questions"
        case measuredDimensions = "measured_dimensions"
        case generatedAt = "generated_at"
        case modelIdentifier = "model_identifier"
    }

    // Hand-written because the defaults matter. A synthesised decoder would
    // throw on any absent key, and this payload is generated prose whose
    // shape grows: the server adding a seventh section must not blank the
    // result screen for everyone on an older build. The six §6.10 sections
    // still decode to empty rather than throwing, and the screen decides what
    // an empty section looks like — a decision the UI can make and a decoder
    // cannot.
    //
    // `secondary_influences` is decoded leniently for a second reason: it is
    // a `style_identity` enum on the wire, and a value this build does not
    // know is a newer server, not a corrupt profile. Unknown entries are
    // skipped, matching `StylePreferenceVector.init(from:)`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryIdentity = try container.decodeIfPresent(StyleIdentity.self, forKey: .primaryIdentity)
        identityBasis = try container.decodeIfPresent(String.self, forKey: .identityBasis) ?? ""
        let rawSecondaries = try container.decodeIfPresent([String].self, forKey: .secondaryInfluences) ?? []
        secondaryInfluences = rawSecondaries.compactMap(StyleIdentity.init(rawValue:))
        palette = try container.decodeIfPresent(StyleDNAPalette.self, forKey: .palette) ?? StyleDNAPalette()
        silhouette = try container.decodeIfPresent(StyleDNASilhouette.self, forKey: .silhouette)
            ?? StyleDNASilhouette()
        signatureOpportunities = try container.decodeIfPresent(
            [StyleDNARecommendation].self, forKey: .signatureOpportunities
        ) ?? []
        wardrobePriorities = try container.decodeIfPresent(
            [StyleDNAPriority].self, forKey: .wardrobePriorities
        ) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        formalityPreference = try container.decodeIfPresent(FormalityLevel.self, forKey: .formalityPreference)
        logoTolerance = try container.decodeIfPresent(Int.self, forKey: .logoTolerance)
        trendTolerance = try container.decodeIfPresent(Int.self, forKey: .trendTolerance)
        accessoryPreference = try container.decodeIfPresent(
            AccessoryPreference.self, forKey: .accessoryPreference
        )
        knownInputs = try container.decodeIfPresent([String].self, forKey: .knownInputs) ?? []
        openQuestions = try container.decodeIfPresent([String].self, forKey: .openQuestions) ?? []
        measuredDimensions = try container.decodeIfPresent([String].self, forKey: .measuredDimensions) ?? []
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .now
        modelIdentifier = try container.decodeIfPresent(String.self, forKey: .modelIdentifier) ?? ""
    }
}

// MARK: - Reading the result

public extension StyleDNA {

    /// `true` when there was not enough on the profile to name a direction.
    ///
    /// The §6.10 screen's own empty state, and a real outcome rather than an
    /// error: the server returns a null identity instead of inventing one
    /// when neither the identity step nor the dress code has been answered.
    var needsMoreInput: Bool { primaryIdentity == nil }

    /// The identity was inferred from something other than the user's own
    /// §6.5 selection, so the screen should present it as a starting point.
    ///
    /// Derived from `identityBasis` being non-empty while the identity itself
    /// came from elsewhere — the server writes that sentence precisely so the
    /// client can tell the two apart without a second boolean to keep in sync.
    var identityWasInferred: Bool {
        primaryIdentity != nil && identityBasis.localizedCaseInsensitiveContains("starting point")
    }

    /// The four summary scalars, applied onto an existing `StyleProfile`.
    ///
    /// Used after a regenerate so a locally-cached profile matches what the
    /// server just wrote, without a second round trip. Only the fields this
    /// endpoint owns are touched — the user's own answers (identity, goals,
    /// fit, the preference vector) are left exactly as they were, because the
    /// server did not change them either.
    func applyingSummary(to profile: StyleProfile) -> StyleProfile {
        var updated = profile
        updated.formalityPreference = formalityPreference
        updated.logoTolerance = logoTolerance
        updated.trendTolerance = trendTolerance
        updated.accessoryPreference = accessoryPreference
        updated.preferredColors = palette.preferredColors
        updated.avoidedColors = palette.avoidedColors
        updated.styleSummary = summary
        return updated
    }
}
