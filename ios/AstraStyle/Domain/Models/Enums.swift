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
public enum LaundryState: String, Codable, CaseIterable, Sendable, Identifiable {
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
public enum AvailabilityState: String, Codable, CaseIterable, Sendable, Identifiable {
    case available
    case inLaundry = "in_laundry"
    case inAlteration = "in_alteration"
    case packedForTravel = "packed_for_travel"
    case lentOut = "lent_out"
    case lost
    case unavailable
}

/// Self-reported or inferred physical condition (spec §6.15 item detail).
public enum ItemCondition: String, Codable, CaseIterable, Sendable, Identifiable {
    case newWithTags = "new_with_tags"
    case likeNew = "like_new"
    case good
    case fair
    case worn
}

/// Garment fit, reused both as a closet item's actual fit and as a user's
/// stated fit preference (spec §6.6).
public enum ItemFit: String, Codable, CaseIterable, Sendable, Identifiable {
    case slim
    case tailored
    case regular
    case relaxed
    case oversized

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .slim: String(localized: "Slim", comment: "Garment fit")
        case .tailored: String(localized: "Tailored", comment: "Garment fit")
        case .regular: String(localized: "Regular", comment: "Garment fit")
        case .relaxed: String(localized: "Relaxed", comment: "Garment fit")
        case .oversized: String(localized: "Oversized", comment: "Garment fit")
        }
    }
}

public enum GarmentPattern: String, Codable, CaseIterable, Sendable, Identifiable {
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
public enum Season: String, Codable, CaseIterable, Sendable, Identifiable {
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

// MARK: - `style_profiles.style_goals`

/// The eight goals spec §6.4 offers as a multi-select.
///
/// Stored as raw strings in the `style_goals` jsonb array rather than as a
/// Postgres enum. Deliberate: the column stays free-text so Kyra can later
/// record a goal a user typed in their own words, while the onboarding UI works
/// from this closed set. A Postgres enum here would make the eight options a
/// migration to change, and §6.4's list is product copy, not schema.
public enum StyleGoal: String, Codable, CaseIterable, Sendable, Identifiable {
    case dressBetterDaily = "dress_better_daily"
    case buildCompleteWardrobe = "build_complete_wardrobe"
    case improveProfessionalImage = "improve_professional_image"
    case prepareForSocialEvents = "prepare_for_social_events"
    case findSignatureStyle = "find_signature_style"
    case shopMoreIntelligently = "shop_more_intelligently"
    case dressForChangingBody = "dress_for_changing_body"
    case packAndTravelBetter = "pack_and_travel_better"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dressBetterDaily: String(localized: "Dress better day to day", comment: "Style goal")
        case .buildCompleteWardrobe: String(localized: "Build a complete wardrobe", comment: "Style goal")
        case .improveProfessionalImage: String(localized: "Improve my professional image", comment: "Style goal")
        case .prepareForSocialEvents: String(localized: "Prepare for dates and social events", comment: "Style goal")
        case .findSignatureStyle: String(localized: "Find a signature style", comment: "Style goal")
        case .shopMoreIntelligently: String(localized: "Shop more intelligently", comment: "Style goal")
        // §2 forbids shaming body type. "Dress for a changing body" is the
        // spec's own wording and is kept verbatim -- it is neutral, it is the
        // user's own framing, and softening it into a euphemism would be worse.
        case .dressForChangingBody: String(localized: "Dress for a changing body", comment: "Style goal")
        case .packAndTravelBetter: String(localized: "Pack and travel better", comment: "Style goal")
        }
    }

    /// One line explaining what choosing this changes about Kyra's advice.
    ///
    /// Present because a multi-select with eight abstract options invites
    /// selecting all eight, which carries no information. Saying what each one
    /// does encourages a real choice.
    public var effect: String {
        switch self {
        case .dressBetterDaily:
            String(localized: "More everyday outfits from what you already own.", comment: "Style goal effect")
        case .buildCompleteWardrobe:
            String(localized: "Kyra flags the gaps worth filling first.", comment: "Style goal effect")
        case .improveProfessionalImage:
            String(localized: "Weights work and client-facing occasions higher.", comment: "Style goal effect")
        case .prepareForSocialEvents:
            String(localized: "More evening and occasion-led suggestions.", comment: "Style goal effect")
        case .findSignatureStyle:
            String(localized: "Fewer, more consistent recommendations over time.", comment: "Style goal effect")
        case .shopMoreIntelligently:
            String(localized: "Cost-per-wear and duplicate warnings before you buy.", comment: "Style goal effect")
        case .dressForChangingBody:
            String(localized: "Fit guidance leads, and updates as measurements change.", comment: "Style goal effect")
        case .packAndTravelBetter:
            String(localized: "Capsule and packing suggestions for trips.", comment: "Style goal effect")
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

    /// Ordered by formality, not by declaration or raw value — `Comparable` is
    /// what lets outfit and product scoring ask "is this dressier than the
    /// occasion calls for?" directly.
    public static func < (lhs: FormalityLevel, rhs: FormalityLevel) -> Bool {
        lhs.ordinal < rhs.ordinal
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
public enum FitIssue: String, Codable, CaseIterable, Sendable, Identifiable {
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

    public var id: String { rawValue }

    /// User-facing label.
    ///
    /// Phrased as what the wearer notices about how clothes FIT, not as a
    /// verdict on his body — "sleeves are usually too long" rather than "short
    /// arms". Same rule as `FitRules` (docs/14 §4): the subject is the garment.
    /// These strings are checked by `scripts/check_ui_conventions.py`.
    public var displayName: String {
        switch self {
        case .broadChest: String(localized: "Jackets pull across the chest", comment: "Fit issue")
        case .narrowShoulders: String(localized: "Shoulders sit wide on me", comment: "Fit issue")
        case .shortTorso: String(localized: "Tops are long on the body", comment: "Fit issue")
        case .longTorso: String(localized: "Tops come up short", comment: "Fit issue")
        case .longLegs: String(localized: "Trousers are short in the leg", comment: "Fit issue")
        case .shortLegs: String(localized: "Trousers need taking up", comment: "Fit issue")
        case .largeThighs: String(localized: "Trousers are tight through the thigh", comment: "Fit issue")
        case .longArms: String(localized: "Sleeves come up short", comment: "Fit issue")
        case .shortArms: String(localized: "Sleeves are long on me", comment: "Fit issue")
        case .tallFrame: String(localized: "Most things are cut short for me", comment: "Fit issue")
        case .shortFrame: String(localized: "Most things are cut long for me", comment: "Fit issue")
        case .other: String(localized: "Something else", comment: "Fit issue")
        }
    }
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

// MARK: - Lifestyle display names
//
// These three enums shipped without labels, so any screen rendering them would
// have shown the raw values — "trades_outdoor", "ultra_casual",
// "multiple_times_week". Not a crash and not a test failure; just a premium app
// showing database identifiers to a paying user.

public extension OccupationCategory {
    var id: String { rawValue }

    /// User-facing label.
    ///
    /// Names the KIND of work rather than a job title, because the point is what
    /// a man has to dress for. "Trades and outdoor work" tells Kyra to stop
    /// recommending unlined wool; "Tradesman" only tells her a word.
    var displayName: String {
        switch self {
        case .corporate: String(localized: "Corporate or office", comment: "Occupation category")
        case .executive: String(localized: "Executive or client-facing", comment: "Occupation category")
        case .creative: String(localized: "Creative or design", comment: "Occupation category")
        case .education: String(localized: "Education", comment: "Occupation category")
        case .healthcare: String(localized: "Healthcare", comment: "Occupation category")
        case .technology: String(localized: "Technology", comment: "Occupation category")
        case .tradesOutdoor: String(localized: "Trades or outdoor work", comment: "Occupation category")
        case .hospitality: String(localized: "Hospitality or service", comment: "Occupation category")
        case .selfEmployed: String(localized: "Self-employed", comment: "Occupation category")
        case .student: String(localized: "Student", comment: "Occupation category")
        case .retired: String(localized: "Retired", comment: "Occupation category")
        case .other: String(localized: "Something else", comment: "Occupation category")
        }
    }
}

public extension DressCode {
    var id: String { rawValue }

    /// User-facing label.
    ///
    /// Described by what it looks like, not by its trade name. A man knows
    /// whether he wears a jacket to work; he may not know whether that counts as
    /// "business casual", and a list of labels he has to decode is a list he
    /// answers wrongly.
    var displayName: String {
        switch self {
        case .ultraCasual: String(localized: "Whatever's clean", comment: "Dress code")
        case .casual: String(localized: "Jeans and a T-shirt", comment: "Dress code")
        case .smartCasual: String(localized: "Good jeans, decent shirt", comment: "Dress code")
        case .businessCasual: String(localized: "Chinos and a collar", comment: "Dress code")
        case .businessFormal: String(localized: "Suit and tie", comment: "Dress code")
        case .blackTie: String(localized: "Black tie", comment: "Dress code")
        case .formal: String(localized: "Formal, but not black tie", comment: "Dress code")
        case .athletic: String(localized: "Athletic or uniform", comment: "Dress code")
        }
    }
}

public extension LaundryCadence {
    var id: String { rawValue }

    /// User-facing label.
    ///
    /// This is the field that decides how many of a thing Kyra can assume you
    /// own. Someone who does laundry monthly needs a fortnight of shirts;
    /// someone who does it twice a week does not — and recommending a
    /// seven-shirt rotation to the second man is how a styling app starts
    /// feeling like it is guessing.
    var displayName: String {
        switch self {
        case .multipleTimesWeek: String(localized: "A few times a week", comment: "Laundry cadence")
        case .weekly: String(localized: "Weekly", comment: "Laundry cadence")
        case .biweekly: String(localized: "Every couple of weeks", comment: "Laundry cadence")
        case .monthly: String(localized: "Monthly", comment: "Laundry cadence")
        case .asNeeded: String(localized: "When I run out", comment: "Laundry cadence")
        }
    }
}

// MARK: - Closet display names
//
// The five enums below are what the Closet grid, the item detail sheet and
// the add/edit form put in front of the user, and until now none of them had
// a label — so every one of those screens would have rendered its raw value:
// "worn_once", "in_alteration", "new_with_tags", "all_season". Same failure
// the lifestyle block above was written to fix, one screen later.
//
// The copy rule for all five: this is a man reading about his own clothes,
// so the label is what he would say out loud about a garment, not what the
// column stores. "In the wash" over "Laundry"; "At the tailor" over
// "In alteration". The raw values are fixed by Postgres (see the note at
// the top of this file) and are deliberately NOT the thing being read.

public extension LaundryState {
    var id: String { rawValue }

    /// User-facing label.
    ///
    /// "Worn once" is the case that earns the whole enum: it is the state a
    /// man is actually in most mornings — the shirt is not dirty and not
    /// fresh — and naming it honestly is what lets Kyra suggest it again
    /// without the app pretending it was never worn.
    var displayName: String {
        switch self {
        case .clean: String(localized: "Clean", comment: "Laundry state")
        case .wornOnce: String(localized: "Worn once", comment: "Laundry state")
        case .laundry: String(localized: "In the wash", comment: "Laundry state")
        case .unavailable: String(localized: "Unavailable", comment: "Laundry state")
        }
    }
}

public extension AvailabilityState {
    var id: String { rawValue }

    /// User-facing label.
    ///
    /// Deliberately overlaps `LaundryState.laundry` in wording ("In the
    /// wash") because the two enums genuinely describe the same real-world
    /// situation from different columns, and inventing a second phrase for
    /// it — "In laundry" — would read as a distinction the user is meant to
    /// understand when there isn't one.
    ///
    /// "At the tailor" rather than "In alteration": one is where the jacket
    /// is, the other is a process noun. The first is the sentence a man
    /// would say.
    var displayName: String {
        switch self {
        case .available: String(localized: "Available", comment: "Item availability")
        case .inLaundry: String(localized: "In the wash", comment: "Item availability")
        case .inAlteration: String(localized: "At the tailor", comment: "Item availability")
        case .packedForTravel: String(localized: "Packed", comment: "Item availability")
        case .lentOut: String(localized: "Lent out", comment: "Item availability")
        case .lost: String(localized: "Lost", comment: "Item availability")
        case .unavailable: String(localized: "Unavailable", comment: "Item availability")
        }
    }
}

public extension ItemCondition {
    var id: String { rawValue }

    /// User-facing label.
    ///
    /// Resale vocabulary ("new with tags", "like new") rather than a 1-5
    /// quality rating, because this is a field the user sets himself and
    /// those are the terms he has already sorted his own wardrobe with on
    /// eBay, Vinted and Grailed. A rating scale would need a legend; these
    /// don't.
    ///
    /// `.worn` reads "Well worn", not "Worn" — `LaundryState.wornOnce` is
    /// two lines away in the same form and "Worn" next to "Worn once" is
    /// two different questions answered with the same word.
    var displayName: String {
        switch self {
        case .newWithTags: String(localized: "New with tags", comment: "Item condition")
        case .likeNew: String(localized: "Like new", comment: "Item condition")
        case .good: String(localized: "Good", comment: "Item condition")
        case .fair: String(localized: "Fair", comment: "Item condition")
        case .worn: String(localized: "Well worn", comment: "Item condition")
        }
    }
}

public extension GarmentPattern {
    var id: String { rawValue }

    /// User-facing label.
    ///
    /// Adjectives, not nouns — "Striped", not "Stripe" — because every one
    /// of these is read in a phrase about a garment ("Striped · Cotton ·
    /// Navy"), never as a category name on its own. `.check` and `.plaid`
    /// stay as nouns since "Checked" and "Plaided" are not how either is
    /// said; they're already used adjectivally ("a check shirt").
    var displayName: String {
        switch self {
        case .solid: String(localized: "Solid", comment: "Garment pattern")
        case .stripe: String(localized: "Striped", comment: "Garment pattern")
        case .check: String(localized: "Check", comment: "Garment pattern")
        case .plaid: String(localized: "Plaid", comment: "Garment pattern")
        case .floral: String(localized: "Floral", comment: "Garment pattern")
        case .print: String(localized: "Print", comment: "Garment pattern")
        case .textured: String(localized: "Textured", comment: "Garment pattern")
        case .camo: String(localized: "Camo", comment: "Garment pattern")
        case .other: String(localized: "Other", comment: "Garment pattern")
        }
    }
}

public extension Season {
    var id: String { rawValue }

    /// User-facing label.
    ///
    /// Two cases where the label deliberately does not track the raw value:
    ///
    /// * `.fall` renders "Autumn". The raw value is fixed by the Postgres
    ///   enum and is not up for renaming, but the app's copy is British
    ///   English throughout ("Trousers", "taking up") and "Fall" in that
    ///   register reads as an American import.
    /// * `.allSeason` renders "All year". "All-season" is a tyre.
    var displayName: String {
        switch self {
        case .spring: String(localized: "Spring", comment: "Season")
        case .summer: String(localized: "Summer", comment: "Season")
        case .fall: String(localized: "Autumn", comment: "Season")
        case .winter: String(localized: "Winter", comment: "Season")
        case .allSeason: String(localized: "All year", comment: "Season")
        }
    }
}
