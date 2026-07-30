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

    /// The furthest step reached, so a resumed draft reopens where it stopped
    /// rather than at the beginning.
    public var furthestStepReached: OnboardingStep = .intro

    public init() {}

    enum CodingKeys: String, CodingKey {
        case goals, selectedIdentities, primaryIdentity, units
        case height, weight, chest, waist, inseam, neck
        case shoeSize, shirtSize, trouserSize, preferredFit, fitIssues
        case skinUndertone, hairColor, eyeColor, facialHair, wearsGlasses, tattoosVisible
        case occupationCategory, dressCode, commonOccasions, climatePreferences
        case laundryCadence, travelFrequency, religiousServiceAttireNeeds
        case sustainabilityPreference, preferredBrands, avoidedBrands
        case monthlyBudget, currency, quizAnswers, furthestStepReached
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goals = try c.decodeIfPresent(Set<StyleGoal>.self, forKey: .goals) ?? []
        selectedIdentities = try c.decodeIfPresent([StyleIdentity].self, forKey: .selectedIdentities) ?? []
        primaryIdentity = try c.decodeIfPresent(StyleIdentity.self, forKey: .primaryIdentity)
        units = try c.decodeIfPresent(UnitsPreference.self, forKey: .units) ?? .imperial
        height = try c.decodeIfPresent(MeasurementEntry.self, forKey: .height) ?? MeasurementEntry()
        weight = try c.decodeIfPresent(MeasurementEntry.self, forKey: .weight) ?? MeasurementEntry()
        chest = try c.decodeIfPresent(MeasurementEntry.self, forKey: .chest) ?? MeasurementEntry()
        waist = try c.decodeIfPresent(MeasurementEntry.self, forKey: .waist) ?? MeasurementEntry()
        inseam = try c.decodeIfPresent(MeasurementEntry.self, forKey: .inseam) ?? MeasurementEntry()
        neck = try c.decodeIfPresent(MeasurementEntry.self, forKey: .neck) ?? MeasurementEntry()
        shoeSize = try c.decodeIfPresent(String.self, forKey: .shoeSize)
        shirtSize = try c.decodeIfPresent(String.self, forKey: .shirtSize)
        trouserSize = try c.decodeIfPresent(String.self, forKey: .trouserSize)
        preferredFit = try c.decodeIfPresent(ItemFit.self, forKey: .preferredFit)
        fitIssues = try c.decodeIfPresent(Set<FitIssue>.self, forKey: .fitIssues) ?? []
        skinUndertone = try c.decodeIfPresent(String.self, forKey: .skinUndertone)
        hairColor = try c.decodeIfPresent(String.self, forKey: .hairColor)
        eyeColor = try c.decodeIfPresent(String.self, forKey: .eyeColor)
        facialHair = try c.decodeIfPresent(String.self, forKey: .facialHair)
        wearsGlasses = try c.decodeIfPresent(Bool.self, forKey: .wearsGlasses)
        tattoosVisible = try c.decodeIfPresent(Bool.self, forKey: .tattoosVisible)
        occupationCategory = try c.decodeIfPresent(OccupationCategory.self, forKey: .occupationCategory)
        dressCode = try c.decodeIfPresent(DressCode.self, forKey: .dressCode)
        commonOccasions = try c.decodeIfPresent([String].self, forKey: .commonOccasions) ?? []
        climatePreferences = try c.decodeIfPresent([String].self, forKey: .climatePreferences) ?? []
        laundryCadence = try c.decodeIfPresent(LaundryCadence.self, forKey: .laundryCadence)
        travelFrequency = try c.decodeIfPresent(String.self, forKey: .travelFrequency)
        religiousServiceAttireNeeds = try c.decodeIfPresent(
            String.self, forKey: .religiousServiceAttireNeeds
        )
        sustainabilityPreference = try c.decodeIfPresent(String.self, forKey: .sustainabilityPreference)
        preferredBrands = try c.decodeIfPresent([String].self, forKey: .preferredBrands) ?? []
        avoidedBrands = try c.decodeIfPresent([String].self, forKey: .avoidedBrands) ?? []
        monthlyBudget = try c.decodeIfPresent(Decimal.self, forKey: .monthlyBudget)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
            ?? Locale.current.currency?.identifier ?? "USD"
        quizAnswers = try c.decodeIfPresent([StylePreferenceQuizAnswer].self, forKey: .quizAnswers) ?? []
        furthestStepReached = try c.decodeIfPresent(
            OnboardingStep.self, forKey: .furthestStepReached
        ) ?? .intro
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(goals, forKey: .goals)
        try c.encode(selectedIdentities, forKey: .selectedIdentities)
        try c.encodeIfPresent(primaryIdentity, forKey: .primaryIdentity)
        try c.encode(units, forKey: .units)
        try c.encode(height, forKey: .height)
        try c.encode(weight, forKey: .weight)
        try c.encode(chest, forKey: .chest)
        try c.encode(waist, forKey: .waist)
        try c.encode(inseam, forKey: .inseam)
        try c.encode(neck, forKey: .neck)
        try c.encodeIfPresent(shoeSize, forKey: .shoeSize)
        try c.encodeIfPresent(shirtSize, forKey: .shirtSize)
        try c.encodeIfPresent(trouserSize, forKey: .trouserSize)
        try c.encodeIfPresent(preferredFit, forKey: .preferredFit)
        try c.encode(fitIssues, forKey: .fitIssues)
        try c.encodeIfPresent(skinUndertone, forKey: .skinUndertone)
        try c.encodeIfPresent(hairColor, forKey: .hairColor)
        try c.encodeIfPresent(eyeColor, forKey: .eyeColor)
        try c.encodeIfPresent(facialHair, forKey: .facialHair)
        try c.encodeIfPresent(wearsGlasses, forKey: .wearsGlasses)
        try c.encodeIfPresent(tattoosVisible, forKey: .tattoosVisible)
        try c.encodeIfPresent(occupationCategory, forKey: .occupationCategory)
        try c.encodeIfPresent(dressCode, forKey: .dressCode)
        try c.encode(commonOccasions, forKey: .commonOccasions)
        try c.encode(climatePreferences, forKey: .climatePreferences)
        try c.encodeIfPresent(laundryCadence, forKey: .laundryCadence)
        try c.encodeIfPresent(travelFrequency, forKey: .travelFrequency)
        try c.encodeIfPresent(religiousServiceAttireNeeds, forKey: .religiousServiceAttireNeeds)
        try c.encodeIfPresent(sustainabilityPreference, forKey: .sustainabilityPreference)
        try c.encode(preferredBrands, forKey: .preferredBrands)
        try c.encode(avoidedBrands, forKey: .avoidedBrands)
        try c.encodeIfPresent(monthlyBudget, forKey: .monthlyBudget)
        try c.encode(currency, forKey: .currency)
        try c.encode(quizAnswers, forKey: .quizAnswers)
        try c.encode(furthestStepReached, forKey: .furthestStepReached)
    }
}

// MARK: - Mapping to the domain models

public extension OnboardingDraft {

    /// §6.5's "choose three, rank one primary" is only satisfied when both
    /// halves are done. Used to gate that step's Continue button, and nothing
    /// else — no other step has a hard requirement.
    var hasCompleteIdentitySelection: Bool {
        selectedIdentities.count == StyleIdentityRules.requiredSelectionCount
            && primaryIdentity != nil
            && selectedIdentities.contains(primaryIdentity!)
    }

    func styleProfile(userID: UUID) -> StyleProfile {
        StyleProfile(
            userID: userID,
            primaryIdentity: primaryIdentity,
            // The primary is excluded from the secondaries rather than
            // duplicated across both columns.
            secondaryIdentities: selectedIdentities.filter { $0 != primaryIdentity },
            styleGoals: goals.map(\.rawValue).sorted(),
            preferredFit: preferredFit
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
            fitNotes: fitIssues.sorted { $0.rawValue < $1.rawValue }
        )
    }

    func lifestyleProfile(userID: UUID) -> LifestyleProfile {
        LifestyleProfile(
            userID: userID,
            occupationCategory: occupationCategory,
            dressCode: dressCode,
            commonOccasions: commonOccasions,
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

    func completionPayload(userID: UUID) -> OnboardingCompletionPayload {
        OnboardingCompletionPayload(
            styleGoals: goals.map(\.rawValue).sorted(),
            styleProfile: styleProfile(userID: userID),
            bodyProfile: bodyProfile(userID: userID),
            lifestyleProfile: lifestyleProfile(userID: userID),
            quizAnswers: quizAnswers
        )
    }
}

public enum StyleIdentityRules {
    /// Spec §6.5: "Ask users to choose three, then rank one primary."
    public static let requiredSelectionCount = 3
}
