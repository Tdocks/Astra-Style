//
//  BodyProfile.swift
//  AstraStyle
//
//  Maps `body_profiles` (spec §9), populated during the measurements-and-fit
//  onboarding step (spec §6.6). All measurement fields are optional — the
//  onboarding flow explicitly allows "I don't know".
//
//  Measurement values are stored as raw `Double`s in the unit indicated by
//  `Profile.units` (inches/pounds for `.imperial`, centimeters/kilograms
//  for `.metric`) rather than as `Measurement<Unit>`, matching the flat
//  numeric columns on the `body_profiles` table. Presentation-layer code
//  should convert via `Core/Utilities/MeasurementFormatting` before display.
//

import Foundation

public struct BodyProfile: Codable, Hashable, Sendable {
    public var userID: UUID
    public var heightValue: Double?
    public var weightValue: Double?
    public var chest: Double?
    public var waist: Double?
    public var inseam: Double?
    public var neck: Double?
    public var shoeSize: String?
    public var shirtSize: String?
    public var trouserSize: String?
    public var fitNotes: [FitIssue]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        userID: UUID,
        heightValue: Double? = nil,
        weightValue: Double? = nil,
        chest: Double? = nil,
        waist: Double? = nil,
        inseam: Double? = nil,
        neck: Double? = nil,
        shoeSize: String? = nil,
        shirtSize: String? = nil,
        trouserSize: String? = nil,
        fitNotes: [FitIssue] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.userID = userID
        self.heightValue = heightValue
        self.weightValue = weightValue
        self.chest = chest
        self.waist = waist
        self.inseam = inseam
        self.neck = neck
        self.shoeSize = shoeSize
        self.shirtSize = shirtSize
        self.trouserSize = trouserSize
        self.fitNotes = fitNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case heightValue = "height_value"
        case weightValue = "weight_value"
        case chest
        case waist
        case inseam
        case neck
        case shoeSize = "shoe_size"
        case shirtSize = "shirt_size"
        case trouserSize = "trouser_size"
        case fitNotes = "fit_notes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
