//
//  Enums.swift
//  AstraStyle
//
//  Shared enumerations for the domain model. Includes every enum given
//  verbatim in spec §26 ("Sample Domain Types") plus the enums implied by
//  the §9 data model's signal/column lists and the §6.19 product verdicts.
//
//  All raw values are lowerCamelCase-free snake-safe strings chosen to
//  match what the Postgres/Edge Function layer is expected to emit, so
//  decoding a Supabase row never requires a translation table beyond the
//  `CodingKeys` already present on each model.
//

import Foundation

// NOTE ON RAW VALUES
// Every raw value below is a member of the corresponding Postgres enum defined
// in supabase/migrations/20260728100100_core_enums.sql. They are not free-form
// strings: a mismatch does not fail at compile time, it fails at INSERT time
// with "invalid input value for enum", which is a slow and confusing way to
// find a typo. If you add a case here, add it to the migration in the same
// change — and vice versa.

// MARK: - Spec §26 (given verbatim)

/// The seven top-level garment categories (spec §26, and the Closet
/// category rail / builder category rail in §6.13-6.14).
public enum ClothingCategory: String, Codable, CaseIterable, Sendable {
    case top
    case bottom
    case outerwear
    case shoes
    case accessory
    case watch
    case fragrance

    public var displayName: String {
        switch self {
        case .top: String(localized: "Tops", comment: "Closet category")
        case .bottom: String(localized: "Bottoms", comment: "Closet category")
        case .outerwear: String(localized: "Outerwear", comment: "Closet category")
        case .shoes: String(localized: "Shoes", comment: "Closet category")
        case .accessory: String(localized: "Accessories", comment: "Closet category")
        case .watch: String(localized: "Watches", comment: "Closet category")
        case .fragrance: String(localized: "Fragrance", comment: "Closet category")
        }
    }
}

/// Whether a closet item is clean, mid-cycle, or unavailable to wear today
/// (spec §26; drives the Home "Laundry/availability alert" module, §6.11).
public enum LaundryState: String, Codable, Sendable {
    case clean
    case wornOnce = "worn_once"
    case laundry
    case unavailable
}

/// Kyra's buy/skip verdict on a candidate purchase (spec §26 and §6.19).
public enum KyraVerdict: String, Codable, Sendable {
    case buy
    case consider
    case waitForSale = "wait_for_sale"
    case skip
}

// MARK: - `closet_items` / `closet_item_images`

/// Whether an owned item is currently available to be worn (distinct from
/// `LaundryState`, which tracks the wash cycle specifically).
public enum AvailabilityState: String, Codable, CaseIterable, Sendable {
    case available
    case inLaundry = "in_laundry"
    case inAlteration = "in_alteration"
    case packedForTravel = "packed_for_travel"
    case lentOut = "lent_out"
    case lost
    case unavailable
}

/// Self-reported or inferred physical condition (spec §6.15 item detail).
public enum ItemCondition: String, Codable, CaseIterable, Sendable {
    case newWithTags = "new_with_tags"
    case likeNew = "like_new"
    case good
    case fair
    case worn
}

/// Garment fit, reused both as a closet item's actual fit and as a user's
/// stated fit preference (spec §6.6).
public enum ItemFit: String, Codable, CaseIterable, Sendable {
    case slim
    case tailored
    case regular
    case relaxed
    case oversized
}

public enum GarmentPattern: String, Codable, CaseIterable, Sendable {
    case solid
    case stripe
    case check
    case plaid
    case floral
    case print
    case textured
    case camo
    case other
}

/// A single season tag; `closet_items.seasonality` stores an array of
/// these (spec §9).
public enum Season: String, Codable, CaseIterable, Sendable {
    case spring
    case summer
    case fall
    case winter
    case allSeason = "all_season"
}

/// `closet_item_images.image_type` (spec §9, driven by scanner capture
/// modes in §6.16).
public enum ClosetImageType: String, Codable, CaseIterable, Sendable {
    case front
    case back
    case label
    case detail
    case onBody = "on_body"
    case other
}

// MARK: - `outfits` / `outfit_items` / `outfit_wears`

/// `outfit_items.role` — which wardrobe slot a garment fills within an outfit.
///
/// This column is typed `clothing_category` in Postgres, so the cases must
/// mirror that type exactly. A previous version added a `layeringPiece` case
/// for the t-shirt-under-a-sweater situation; it was removed because
/// `clothing_category` has no such member and every insert using it would have
/// failed. Supporting layering properly means giving `outfit_items.role` its
/// own `outfit_item_role` enum in a new migration rather than borrowing
/// `clothing_category` — a product decision, not a rename.
public enum OutfitItemRole: String, Codable, CaseIterable, Sendable {
    case top
    case bottom
    case outerwear
    case shoes
    case accessory
    case watch
    case fragrance
}

/// `outfits.source` — how the outfit came to exist.
///
/// These four cases mirror the Postgres `outfit_source` type exactly.
///
/// - `aiGenerated`: produced by `POST /outfits/generate` (spec §5.4). This is
///   the case `LiveOutfitRepository.saveOutfit` writes.
/// - `userCreated`: assembled by hand in the outfit builder (spec §6.13).
/// - `kyraSuggested`: proposed by Kyra inside a conversation (spec §6.20).
/// - `studioDerived`: originated from a Style Studio generation (spec §6.17).
public enum OutfitSource: String, Codable, CaseIterable, Sendable {
    case aiGenerated = "ai_generated"
    case userCreated = "user_created"
    case kyraSuggested = "kyra_suggested"
    case studioDerived = "studio_derived"
}

// MARK: - `style_feedback`

/// `style_feedback.target_type` — what a feedback row is about.
public enum StyleFeedbackTargetType: String, Codable, Sendable {
    case closetItem = "closet_item"
    case outfit
    /// Feedback on one garment's role *within* an outfit, as opposed to the
    /// item in isolation — "the shoes were wrong here" (spec §9 signals).
    case outfitItem = "outfit_item"
    case productCandidate = "product_candidate"
}

/// `style_feedback.signal` (spec §9 "Signals" list, verbatim).
public enum StyleFeedbackSignal: String, Codable, CaseIterable, Sendable {
    case like
    case dislike
    case wore
    case skipped
    case saved
    case purchased
    case returned
    case tooFormal = "too_formal"
    case tooCasual = "too_casual"
    case badFit = "bad_fit"
    case wrongColor = "wrong_color"
}

// MARK: - `occasions`

public enum OccasionSource: String, Codable, Sendable {
    case manual
    case calendarSync = "calendar_sync"
    case aiSuggested = "ai_suggested"
}

// MARK: - `kyra_threads` / `kyra_messages`

public enum KyraMessageRole: String, Codable, Sendable {
    case system
    case user
    /// Kyra's own turns. The raw value is `assistant` because that is what the
    /// Postgres `kyra_message_role` type and every model provider's chat
    /// format call it; `kyra` is the product name, not the wire value.
    case assistant
    /// A tool-call result turn (spec §11 lists 11 server tools Kyra can call).
    case tool
}

/// The `intent` field of Kyra's structured response schema (spec §11).
public enum KyraIntent: String, Codable, Sendable {
    case dailyOutfit = "daily_outfit"
    case productAdvice = "product_advice"
    case outfitReview = "outfit_review"
    case packing
    case education
    case general
}

// MARK: - `style_memories`

public enum StyleMemoryType: String, Codable, CaseIterable, Sendable {
    case preference
    case dislike
    case fitNote = "fit_note"
    case brandAffinity = "brand_affinity"
    case budgetNote = "budget_note"
    case sizingNote = "sizing_note"
    case general
}

// MARK: - `studio_generations`

public enum StudioGenerationStatus: String, Codable, Sendable {
    case queued
    case generating
    case complete
    case failed
}

// MARK: - `subscriptions`

public enum SubscriptionStatus: String, Codable, Sendable {
    case trialing
    case active
    case inGracePeriod = "in_grace_period"
    case inBillingRetry = "in_billing_retry"
    case expired
    case revoked
    case cancelled
}

public enum SubscriptionEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

/// `profiles.subscription_tier`.
public enum SubscriptionTier: String, Codable, Sendable {
    case free
    case premium
}

// MARK: - `profiles`

public enum UnitsPreference: String, Codable, Sendable {
    case imperial
    case metric
}

/// `profiles.theme`. Also used directly by `App/AppContainer.swift`'s
/// `AppSettings.preferredColorScheme` — see `ThemePreference.resolvedColorScheme`
/// in `App/AstraStyleApp.swift` for the bridge to SwiftUI's `ColorScheme?`.
public enum ThemePreference: String, Codable, Sendable {
    case system
    case light
    case dark
}

// MARK: - `style_profiles`

/// The ten style identities offered in onboarding (spec §6.5).
public enum StyleIdentity: String, Codable, CaseIterable, Sendable {
    case modernHeritage = "modern_heritage"
    case quietLuxury = "quiet_luxury"
    case smartCasual = "smart_casual"
    case minimalist
    case luxuryStreetwear = "luxury_streetwear"
    case ruggedUtility = "rugged_utility"
    case classicAmericana = "classic_americana"
    case europeanSummer = "european_summer"
    case executive
    case creative

    public var displayName: String {
        switch self {
        case .modernHeritage: String(localized: "Modern Heritage")
        case .quietLuxury: String(localized: "Quiet Luxury")
        case .smartCasual: String(localized: "Smart Casual")
        case .minimalist: String(localized: "Minimalist")
        case .luxuryStreetwear: String(localized: "Luxury Streetwear")
        case .ruggedUtility: String(localized: "Rugged Utility")
        case .classicAmericana: String(localized: "Classic Americana")
        case .europeanSummer: String(localized: "European Summer")
        case .executive: String(localized: "Executive")
        case .creative: String(localized: "Creative")
        }
    }
}

/// A coarse formality scale used for `style_profiles.formality_preference`
/// and for scoring outfits/products against lifestyle fit.
public enum FormalityLevel: String, Codable, CaseIterable, Sendable, Comparable {
    case veryCasual = "very_casual"
    case casual
    case balanced
    case formal
    case veryFormal = "very_formal"

    /// Position on the five-point scale, for comparisons and slider binding.
    public var ordinal: Int {
        switch self {
        case .veryCasual: 0
        case .casual: 1
        case .balanced: 2
        case .formal: 3
        case .veryFormal: 4
        }
    }
}

/// Generic low/medium/high tolerance scale, reused for
/// `logo_tolerance` and `trend_tolerance`.
public enum ToleranceLevel: String, Codable, CaseIterable, Sendable {
    case none
    case low
    case medium
    case high
}

public enum AccessoryPreference: String, Codable, CaseIterable, Sendable {
    case minimal
    case moderate
    case bold
}

// MARK: - `body_profiles`

/// Common fit issues surfaced during measurement onboarding (spec §6.6,
/// "broad chest, short torso, long legs, large thighs, etc").
public enum FitIssue: String, Codable, CaseIterable, Sendable {
    case broadChest = "broad_chest"
    case narrowShoulders = "narrow_shoulders"
    case shortTorso = "short_torso"
    case longTorso = "long_torso"
    case longLegs = "long_legs"
    case shortLegs = "short_legs"
    case largeThighs = "large_thighs"
    case longArms = "long_arms"
    case shortArms = "short_arms"
    case tallFrame = "tall_frame"
    case shortFrame = "short_frame"
    case other
}

// MARK: - `lifestyle_profiles`

public enum OccupationCategory: String, Codable, CaseIterable, Sendable {
    case corporate
    case executive
    case creative
    case education
    case healthcare
    case technology
    case tradesOutdoor = "trades_outdoor"
    case hospitality
    case selfEmployed = "self_employed"
    case student
    case retired
    case other
}

public enum DressCode: String, Codable, CaseIterable, Sendable {
    case ultraCasual = "ultra_casual"
    case casual
    case smartCasual = "smart_casual"
    case businessCasual = "business_casual"
    case businessFormal = "business_formal"
    case blackTie = "black_tie"
    case formal
    case athletic
}

public enum LaundryCadence: String, Codable, CaseIterable, Sendable {
    case multipleTimesWeek = "multiple_times_week"
    case weekly
    case biweekly
    case monthly
    case asNeeded = "as_needed"
}
