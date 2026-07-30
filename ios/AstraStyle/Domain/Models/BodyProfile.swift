//
//  BodyProfile.swift
//  AstraStyle
//
//  Maps `body_profiles` (spec §9), populated during the measurements-and-fit
//  onboarding step (spec §6.6). All measurement fields are optional — the
//  onboarding flow explicitly allows "I don't know", and null IS that answer
//  (the table comment says so; there is no sentinel value).
//
//  UNITS: every measurement is stored in CENTIMETRES (weight in kilograms),
//  always, regardless of `Profile.units`. That column controls display
//  formatting on the client and nothing else. The migration
//  (20260728100200_profiles_and_identity.sql) is explicit about this and it is
//  the right call — unit-tagged numeric columns whose unit lives on a
//  different table are ambiguous at every read site.
//
//  The property names carry the `Cm` / `Kg` suffix for the same reason the
//  columns do. A property called `chest` invites a caller to put inches in it,
//  and nothing downstream can tell.
//
//  ────────────────────────────────────────────────────────────────────────
//  This file previously declared `heightValue`, `chest`, `waist`, `inseam` and
//  `neck` against coding keys `height_value`, `chest`, `waist`, `inseam`,
//  `neck` — none of which exist on the table. Because every property is
//  Optional, Swift's synthesised decoder uses `decodeIfPresent` and therefore
//  did NOT throw: it silently decoded every measurement as nil, forever, for
//  every user. A body profile round-tripped through the API came back empty
//  and looked exactly like a user who had skipped the step.
//
//  Nothing caught it because nothing consumed the measurements yet, and the
//  failure mode of "all nil" is indistinguishable from the legitimate "I don't
//  know" case that the whole feature is built to tolerate. `scripts/
//  check_column_drift.py` now checks coding keys against the migrations, which
//  is the guard that would have caught this on the day it was written.
//  ────────────────────────────────────────────────────────────────────────
//

import Foundation

public struct BodyProfile: Codable, Hashable, Sendable {
    public var userID: UUID
    public var heightCm: Double?
    public var weightKg: Double?
    public var chestCm: Double?
    public var waistCm: Double?
    public var inseamCm: Double?
    public var neckCm: Double?
    public var shoeSize: String?
    public var shirtSize: String?
    public var trouserSize: String?
    public var fitNotes: [FitIssue]
    /// Spec §6.7's optional appearance attributes, stored in the `appearance`
    /// jsonb column.
    ///
    /// Non-optional with an empty default, because the column is
    /// `not null default '{}'` — modelling it as `AppearanceProfile?` would let
    /// a caller write nil into a NOT NULL column and only find out at the
    /// server.
    public var appearance: AppearanceProfile
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        userID: UUID,
        heightCm: Double? = nil,
        weightKg: Double? = nil,
        chestCm: Double? = nil,
        waistCm: Double? = nil,
        inseamCm: Double? = nil,
        neckCm: Double? = nil,
        shoeSize: String? = nil,
        shirtSize: String? = nil,
        trouserSize: String? = nil,
        fitNotes: [FitIssue] = [],
        appearance: AppearanceProfile = AppearanceProfile(),
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.userID = userID
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.chestCm = chestCm
        self.waistCm = waistCm
        self.inseamCm = inseamCm
        self.neckCm = neckCm
        self.shoeSize = shoeSize
        self.shirtSize = shirtSize
        self.trouserSize = trouserSize
        self.fitNotes = fitNotes
        self.appearance = appearance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case heightCm = "height_value_cm"
        case weightKg = "weight_value_kg"
        case chestCm = "chest_cm"
        case waistCm = "waist_cm"
        case inseamCm = "inseam_cm"
        case neckCm = "neck_cm"
        case shoeSize = "shoe_size"
        case shirtSize = "shirt_size"
        case trouserSize = "trouser_size"
        case fitNotes = "fit_notes"
        case appearance
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public extension BodyProfile {
    /// Inches, for the imperial display path and for the tailoring maths.
    ///
    /// The drop bands in `FrameDerivation` are stated in inches because that is
    /// how suits are actually graded — a "7 drop" is a real, named thing in the
    /// trade and converting it to 17.78cm would obscure rather than clarify.
    static func inches(fromCm value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value / 2.54
    }
}
