//
//  OnboardingDraft.swift
//  AstraStyle
//
//  Everything collected across spec §6.3–§6.10, held as one value type while
//  the user works through the flow and submitted in a single call at the end.
//
//  Three properties of this type are load-bearing.
//
//  1. EVERY ANSWER IS OPTIONAL OR EMPTY-CAPABLE. Spec §6.6 requires "I don't
//     know" on every measurement, §6.7 is optional in full, and a user can
//     abandon the flow at any step. There is no such thing as a partially
//     invalid draft — only a draft with fewer answers.
//
//  2. "I DON'T KNOW" IS AN ANSWER, NOT AN ABSENCE. See `MeasurementEntry`.
//     Collapsing "skipped" into nil loses the difference between a user who has
//     not reached the height field and one who deliberately declined it, and
//     that difference decides whether the flow may prompt him again.
//
//  3. IT IS CODABLE AND FLAT. The draft is persisted locally after every step
//     (see `OnboardingDraftStore`) because this flow is eight screens long. A
//     user who gets a phone call at step six and returns to find an empty form
//     will not do it twice.
//

import Foundation

// MARK: - Measurement entry

/// One measurement, in the unit the user typed it in, plus the explicit
/// "I don't know" state spec §6.6 demands.
///
/// Storing the entered unit rather than converting immediately is deliberate.
/// If a user types 71 with `.imperial` selected and later switches the toggle,
/// the number he typed must not silently become 71cm. Conversion happens once,
/// at submission, in `centimetres` — and `body_profiles` is canonically metric
/// (see `BodyProfile`), which is where a naive implementation loses a factor of
/// 2.54.
public struct MeasurementEntry: Codable, Hashable, Sendable {
    public enum State: String, Codable, Sendable {
        /// Not yet reached or left untouched.
        case unanswered
        /// The user explicitly said he does not know.
        case declined
        /// A value was entered.
        case provided
    }

    public var state: State
    /// The number as typed, in `unit`. Meaningless unless `state == .provided`.
    public var value: Double?
    public var unit: UnitsPreference

    public init(state: State = .unanswered, value: Double? = nil, unit: UnitsPreference = .imperial) {
        self.state = state
        self.value = value
        self.unit = unit
    }

    public static func declined(unit: UnitsPreference) -> MeasurementEntry {
        MeasurementEntry(state: .declined, value: nil, unit: unit)
    }

    public static func provided(_ value: Double, unit: UnitsPreference) -> MeasurementEntry {
        MeasurementEntry(state: .provided, value: value, unit: unit)
    }

    /// Converted to centimetres for `body_profiles`, or nil when there is no
    /// value to convert.
    ///
    /// The inch→cm factor is applied here and nowhere else, so there is exactly
    /// one place this can be wrong.
    public var centimetres: Double? {
        guard state == .provided, let value, value > 0 else { return nil }
        return unit == .metric ? value : value * 2.54
    }

    /// Converted to kilograms, for the one field that is a mass rather than a
    /// length. Separate from `centimetres` because a single "convert" that
    /// guessed which unit family a field belonged to would be a trap.
    public var kilograms: Double? {
        guard state == .provided, let value, value > 0 else { return nil }
        return unit == .metric ? value : value * 0.45359237
    }

    /// `true` when the user has engaged with this field at all, either way.
    public var isAnswered: Bool { state != .unanswered }
}

// MARK: - Draft

public struct OnboardingDraft: Codable, Hashable, Sendable {

    // §6.4 — Style goals. Multi-select, no minimum: a user who wants none of
    // the eight is telling us something, and forcing a pick would record noise.
    public var goals: Set<StyleGoal> = []

    // §6.5 — Style identity. Exactly three, then one nominated primary.
    // Ordered rather than a Set: the order the user picked is itself weak
    // preference signal, and a Set would discard it.
    public var selectedIdentities: [StyleIdentity] = []
    public var primaryIdentity: StyleIdentity?

    // §6.6 — Measurements and fit.
    public var units: UnitsPreference = .imperial
    public var height = MeasurementEntry()
    public var weight = MeasurementEntry()
    public var chest = MeasurementEntry()
    public var waist = MeasurementEntry()
    public var inseam = MeasurementEntry()
    public var neck = MeasurementEntry()
    public var shoeSize: String?
    public var shirtSize: String?
    public var trouserSize: String?
    public var preferredFit: ItemFit?
    public var fitIssues: Set<FitIssue> = []

    // §6.7 — Appearance. Optional in full; stored in `body_profiles.appearance`
    // as jsonb, so free-form strings rather than enums.
    public var skinUndertone: String?
    public var hairColor: String?
    public var eyeColor: String?
    public var facialHair: String?
    public var wearsGlasses: Bool?
    public var tattoosVisible: Bool?

    // §6.8 — Lifestyle.
    public var occupationCategory: OccupationCategory?
    public var dressCode: DressCode?
    public var typicalWeek: String?
    public var commonOccasions: [String] = []
    public var climatePreferences: [String] = []
    public var laundryCadence: LaundryCadence?
    public var travelFrequency: String?
    public var religiousServiceAttireNeeds: String?
    public var sustainabilityPreference: String?
    public var preferredBrands: [String] = []
    public var avoidedBrands: [String] = []
    public var monthlyBudget: Decimal?
    /// ISO 4217. Defaults from the device locale rather than to USD, because a
    /// budget shown back to the user in the wrong currency reads as a bug on the
    /// very first screen that mentions money.
    public var currency: String = Locale.current.currency?.identifier ?? "USD"

    // §6.9 — Preference quiz.
    public var quizAnswers: [StylePreferenceQuizAnswer] = []

    /// Optional one-guy referral. Skippable. Applied after complete-onboarding.
    /// Optional so old persisted drafts still decode.
    public var referralCode: String?

    // §5.1 step 11 — optional reference photo.
    //
    // THREE FIELDS RATHER THAN ONE, AND NONE OF THEM IS THE IMAGE.
    //
    // 1. `referenceConsentGrantedAt` is a timestamp, not a Bool, because §29
    //    asks for informed consent obtained BEFORE collection and "he agreed,
    //    at this moment" is the only form of that claim worth persisting. A
    //    Bool cannot distinguish consent given under this build's wording from
    //    consent given under an older one, and the wording is the consent.
    // 2. `referenceImageFilename` names a file in `ReferenceImageStore`, not
    //    the bytes. A JPEG base64'd into this struct would be written to disk
    //    again on every keystroke of every later step, since the flow persists
    //    the whole draft on each change.
    // 3. `referenceStoragePaths` is what actually reaches `body_profiles`
    //    (`AppearanceProfile.referenceSelfiePaths`, §15's
    //    `users/{user_id}/references/...`). Empty until the image has been
    //    uploaded, which is deliberately not at capture time — see
    //    `OnboardingViewModel.uploadReferenceImageIfNeeded()`.
    public var referenceConsentGrantedAt: Date?
    public var referenceImageFilename: String?
    public var referenceStoragePaths: [String] = []

    /// The furthest step reached, so a resumed draft reopens where it stopped
    /// rather than at the beginning.
    public var furthestStepReached: OnboardingStep = .intro

    public init() {}

    enum CodingKeys: String, CodingKey {
        case goals, selectedIdentities, primaryIdentity, units
        case height, weight, chest, waist, inseam, neck
        case shoeSize, shirtSize, trouserSize, preferredFit, fitIssues
        case skinUndertone, hairColor, eyeColor, facialHair, wearsGlasses, tattoosVisible
        case occupationCategory, dressCode, typicalWeek, commonOccasions, climatePreferences
        case laundryCadence, travelFrequency, religiousServiceAttireNeeds
        case sustainabilityPreference, preferredBrands, avoidedBrands
        case monthlyBudget, currency, quizAnswers, furthestStepReached
        case referenceConsentGrantedAt, referenceImageFilename, referenceStoragePaths
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goals = try container.decodeIfPresent(Set<StyleGoal>.self, forKey: .goals) ?? []
        selectedIdentities = try container.decodeIfPresent([StyleIdentity].self, forKey: .selectedIdentities) ?? []
        primaryIdentity = try container.decodeIfPresent(StyleIdentity.self, forKey: .primaryIdentity)
        units = try container.decodeIfPresent(UnitsPreference.self, forKey: .units) ?? .imperial
        height = try container.decodeIfPresent(MeasurementEntry.self, forKey: .height) ?? MeasurementEntry()
        weight = try container.decodeIfPresent(MeasurementEntry.self, forKey: .weight) ?? MeasurementEntry()
        chest = try container.decodeIfPresent(MeasurementEntry.self, forKey: .chest) ?? MeasurementEntry()
        waist = try container.decodeIfPresent(MeasurementEntry.self, forKey: .waist) ?? MeasurementEntry()
        inseam = try container.decodeIfPresent(MeasurementEntry.self, forKey: .inseam) ?? MeasurementEntry()
        neck = try container.decodeIfPresent(MeasurementEntry.self, forKey: .neck) ?? MeasurementEntry()
        shoeSize = try container.decodeIfPresent(String.self, forKey: .shoeSize)
        shirtSize = try container.decodeIfPresent(String.self, forKey: .shirtSize)
        trouserSize = try container.decodeIfPresent(String.self, forKey: .trouserSize)
        preferredFit = try container.decodeIfPresent(ItemFit.self, forKey: .preferredFit)
        fitIssues = try container.decodeIfPresent(Set<FitIssue>.self, forKey: .fitIssues) ?? []
        skinUndertone = try container.decodeIfPresent(String.self, forKey: .skinUndertone)
        hairColor = try container.decodeIfPresent(String.self, forKey: .hairColor)
        eyeColor = try container.decodeIfPresent(String.self, forKey: .eyeColor)
        facialHair = try container.decodeIfPresent(String.self, forKey: .facialHair)
        wearsGlasses = try container.decodeIfPresent(Bool.self, forKey: .wearsGlasses)
        tattoosVisible = try container.decodeIfPresent(Bool.self, forKey: .tattoosVisible)
        occupationCategory = try container.decodeIfPresent(OccupationCategory.self, forKey: .occupationCategory)
        dressCode = try container.decodeIfPresent(DressCode.self, forKey: .dressCode)
        typicalWeek = try container.decodeIfPresent(String.self, forKey: .typicalWeek)
        commonOccasions = try container.decodeIfPresent([String].self, forKey: .commonOccasions) ?? []
        climatePreferences = try container.decodeIfPresent([String].self, forKey: .climatePreferences) ?? []
        laundryCadence = try container.decodeIfPresent(LaundryCadence.self, forKey: .laundryCadence)
        travelFrequency = try container.decodeIfPresent(String.self, forKey: .travelFrequency)
        religiousServiceAttireNeeds = try container.decodeIfPresent(
            String.self, forKey: .religiousServiceAttireNeeds
        )
        sustainabilityPreference = try container.decodeIfPresent(String.self, forKey: .sustainabilityPreference)
        preferredBrands = try container.decodeIfPresent([String].self, forKey: .preferredBrands) ?? []
        avoidedBrands = try container.decodeIfPresent([String].self, forKey: .avoidedBrands) ?? []
        monthlyBudget = try container.decodeIfPresent(Decimal.self, forKey: .monthlyBudget)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
            ?? Locale.current.currency?.identifier ?? "USD"
        quizAnswers = try container.decodeIfPresent([StylePreferenceQuizAnswer].self, forKey: .quizAnswers) ?? []
        furthestStepReached = try container.decodeIfPresent(
            OnboardingStep.self, forKey: .furthestStepReached
        ) ?? .intro
        referenceConsentGrantedAt = try container.decodeIfPresent(Date.self, forKey: .referenceConsentGrantedAt)
        referenceImageFilename = try container.decodeIfPresent(String.self, forKey: .referenceImageFilename)
        referenceStoragePaths = try container.decodeIfPresent([String].self, forKey: .referenceStoragePaths) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(goals, forKey: .goals)
        try container.encode(selectedIdentities, forKey: .selectedIdentities)
        try container.encodeIfPresent(primaryIdentity, forKey: .primaryIdentity)
        try container.encode(units, forKey: .units)
        try container.encode(height, forKey: .height)
        try container.encode(weight, forKey: .weight)
        try container.encode(chest, forKey: .chest)
        try container.encode(waist, forKey: .waist)
        try container.encode(inseam, forKey: .inseam)
        try container.encode(neck, forKey: .neck)
        try container.encodeIfPresent(shoeSize, forKey: .shoeSize)
        try container.encodeIfPresent(shirtSize, forKey: .shirtSize)
        try container.encodeIfPresent(trouserSize, forKey: .trouserSize)
        try container.encodeIfPresent(preferredFit, forKey: .preferredFit)
        try container.encode(fitIssues, forKey: .fitIssues)
        try container.encodeIfPresent(skinUndertone, forKey: .skinUndertone)
        try container.encodeIfPresent(hairColor, forKey: .hairColor)
        try container.encodeIfPresent(eyeColor, forKey: .eyeColor)
        try container.encodeIfPresent(facialHair, forKey: .facialHair)
        try container.encodeIfPresent(wearsGlasses, forKey: .wearsGlasses)
        try container.encodeIfPresent(tattoosVisible, forKey: .tattoosVisible)
        try container.encodeIfPresent(occupationCategory, forKey: .occupationCategory)
        try container.encodeIfPresent(dressCode, forKey: .dressCode)
        try container.encodeIfPresent(typicalWeek, forKey: .typicalWeek)
        try container.encode(commonOccasions, forKey: .commonOccasions)
        try container.encode(climatePreferences, forKey: .climatePreferences)
        try container.encodeIfPresent(laundryCadence, forKey: .laundryCadence)
        try container.encodeIfPresent(travelFrequency, forKey: .travelFrequency)
        try container.encodeIfPresent(religiousServiceAttireNeeds, forKey: .religiousServiceAttireNeeds)
        try container.encodeIfPresent(sustainabilityPreference, forKey: .sustainabilityPreference)
        try container.encode(preferredBrands, forKey: .preferredBrands)
        try container.encode(avoidedBrands, forKey: .avoidedBrands)
        try container.encodeIfPresent(monthlyBudget, forKey: .monthlyBudget)
        try container.encode(currency, forKey: .currency)
        try container.encode(quizAnswers, forKey: .quizAnswers)
        try container.encode(furthestStepReached, forKey: .furthestStepReached)
        try container.encodeIfPresent(referenceConsentGrantedAt, forKey: .referenceConsentGrantedAt)
        try container.encodeIfPresent(referenceImageFilename, forKey: .referenceImageFilename)
        try container.encode(referenceStoragePaths, forKey: .referenceStoragePaths)
    }
}

// MARK: - Mapping to the domain models

public extension OnboardingDraft {

    /// §6.5's "choose three, rank one primary" is only satisfied when both
    /// halves are done. Used to gate that step's Continue button, and nothing
    /// else — no other step has a hard requirement.
    var hasCompleteIdentitySelection: Bool {
        guard let primaryIdentity else { return false }
        return selectedIdentities.count == StyleIdentityRules.requiredSelectionCount
            && selectedIdentities.contains(primaryIdentity)
    }

    /// - Parameter quizCatalog: The comparison set the answers were given
    ///   against. Required rather than defaulted to `.bundled()`, because that
    ///   default would do file I/O on an innocuous-looking call and, worse,
    ///   would silently score a restored draft against whatever imagery THIS
    ///   build happens to have. Passing it makes the dependency visible at every
    ///   call site — there is only one in production, and it hands over the
    ///   catalog the user was actually shown.
    func styleProfile(userID: UUID, quizCatalog: StyleQuizCatalog) -> StyleProfile {
        let engine = StyleQuizEngine(catalog: quizCatalog)
        return StyleProfile(
            userID: userID,
            primaryIdentity: primaryIdentity,
            // The primary is excluded from the secondaries rather than
            // duplicated across both columns.
            secondaryIdentities: selectedIdentities.filter { $0 != primaryIdentity },
            styleGoals: goals.map(\.rawValue).sorted(),
            preferredFit: preferredFit,
            // Derived at submission rather than stored on the draft. The answers
            // are the source of truth; a cached vector alongside them is a second
            // one, and the two drift the first time an answer is changed by the
            // quiz's undo. Deriving also means a draft restored into a build with
            // different imagery is re-scored against the imagery that build has,
            // instead of carrying a number computed from comparisons that no
            // longer exist.
            preferenceVector: engine.vector(from: quizAnswers)
        )
    }

    /// The §6.7 answers, as they are stored.
    ///
    /// Split out so it is obvious that every appearance field reaches
    /// `BodyProfile.appearance`. Before this existed the six §6.7 properties
    /// lived on the draft, were written by the screen, and were then dropped on
    /// the floor by `bodyProfile(userID:)` — collected and never persisted,
    /// the same shape of bug as the coding-key drift in BodyProfile's header.
    var appearanceProfile: AppearanceProfile {
        AppearanceProfile(
            skinUndertone: skinUndertone,
            hairColor: hairColor,
            eyeColor: eyeColor,
            facialHair: facialHair,
            wearsGlasses: wearsGlasses,
            tattoosVisible: tattoosVisible,
            // Only ever the paths of images that have actually been uploaded.
            // A local, not-yet-uploaded capture contributes nothing here: a
            // path in `body_profiles` that resolves to no storage object is
            // worse than an absent one, because every later reader treats it
            // as a reference that exists.
            referenceSelfiePaths: referenceStoragePaths
        )
    }

    func bodyProfile(userID: UUID) -> BodyProfile {
        BodyProfile(
            userID: userID,
            heightCm: height.centimetres,
            weightKg: weight.kilograms,
            chestCm: chest.centimetres,
            waistCm: waist.centimetres,
            inseamCm: inseam.centimetres,
            neckCm: neck.centimetres,
            shoeSize: shoeSize,
            shirtSize: shirtSize,
            trouserSize: trouserSize,
            fitNotes: fitIssues.sorted { $0.rawValue < $1.rawValue },
            appearance: appearanceProfile
        )
    }

    func lifestyleProfile(userID: UUID) -> LifestyleProfile {
        LifestyleProfile(
            userID: userID,
            occupationCategory: occupationCategory,
            dressCode: dressCode,
            commonOccasions: commonOccasions,
            typicalWeek: typicalWeek,
            climatePreferences: climatePreferences,
            monthlyBudget: monthlyBudget,
            currency: currency,
            preferredBrands: preferredBrands,
            avoidedBrands: avoidedBrands,
            laundryCadence: laundryCadence,
            travelFrequency: travelFrequency,
            religiousServiceAttireNeeds: religiousServiceAttireNeeds,
            sustainabilityPreference: sustainabilityPreference
        )
    }

    func completionPayload(userID: UUID, quizCatalog: StyleQuizCatalog) -> OnboardingCompletionPayload {
        OnboardingCompletionPayload(
            styleGoals: goals.map(\.rawValue).sorted(),
            styleProfile: styleProfile(userID: userID, quizCatalog: quizCatalog),
            bodyProfile: bodyProfile(userID: userID),
            lifestyleProfile: lifestyleProfile(userID: userID),
            // Sent as well as the derived vector, not instead of it. The server
            // owns Style DNA generation (§6.10) and may weigh the raw choices
            // differently, or re-infer them entirely when the comparison set
            // grows — which it cannot do from a vector alone.
            quizAnswers: quizAnswers
        )
    }
}

public enum StyleIdentityRules {
    /// Spec §6.5: "Ask users to choose three, then rank one primary."
    public static let requiredSelectionCount = 3
}
