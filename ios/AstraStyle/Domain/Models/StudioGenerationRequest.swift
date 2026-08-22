//
//  StudioGenerationRequest.swift
//  AstraStyle
//
//  Request payload for `POST /studio/generate` (spec §14), covering the
//  Style Studio controls in spec §6.17 (prompt presets + advanced
//  controls) and the safety requirements in spec §13.
//

import Foundation

public struct StudioGenerationRequest: Sendable {
    public var referenceImagePath: String
    public var outfitID: UUID?
    public var adHocItemIDs: [UUID]
    public var preset: StudioPromptPreset?
    public var preserveFace: Bool
    public var preserveBodyProportions: Bool
    public var preserveHair: Bool
    public var background: StudioBackground
    public var pose: StudioPose
    public var formality: FormalityLevel?
    public var season: Season?
    public var colorPalette: [String]

    /// The user must have explicitly consented to processing this specific
    /// reference image (spec §6.17 Safety: "Require user ownership/
    /// permission for personal images"). The repository/Edge Function is
    /// expected to reject a request where this is `false`.
    public var hasUserConsent: Bool

    /// Must match `StudioConsentTerms.currentVersion` / the Edge Function
    /// `CURRENT_STUDIO_CONSENT_TERMS_VERSION`. Stale values 400.
    public var consentTermsVersion: String

    public init(
        referenceImagePath: String,
        outfitID: UUID? = nil,
        adHocItemIDs: [UUID] = [],
        preset: StudioPromptPreset? = nil,
        preserveFace: Bool = true,
        preserveBodyProportions: Bool = true,
        preserveHair: Bool = true,
        background: StudioBackground = .studio,
        pose: StudioPose = .standingFront,
        formality: FormalityLevel? = nil,
        season: Season? = nil,
        colorPalette: [String] = [],
        hasUserConsent: Bool,
        consentTermsVersion: String = StudioConsentTerms.currentVersion
    ) {
        self.referenceImagePath = referenceImagePath
        self.outfitID = outfitID
        self.adHocItemIDs = adHocItemIDs
        self.preset = preset
        self.preserveFace = preserveFace
        self.preserveBodyProportions = preserveBodyProportions
        self.preserveHair = preserveHair
        self.background = background
        self.pose = pose
        self.formality = formality
        self.season = season
        self.colorPalette = colorPalette
        self.hasUserConsent = hasUserConsent
        self.consentTermsVersion = consentTermsVersion
    }
}

/// Spec §6.17 "Prompt presets".
public enum StudioPromptPreset: String, Codable, CaseIterable, Sendable {
    case smartCasual = "smart_casual"
    case dateNight = "date_night"
    case wedding
    case vacation
    case executive
    case oldMoneyInspired = "old_money_inspired"
    case minimalist
    case nightOut = "night_out"
}

public enum StudioBackground: String, Codable, CaseIterable, Sendable {
    case studio
    case editorialOutdoor = "editorial_outdoor"
    case urban
    case neutral
}

public enum StudioPose: String, Codable, CaseIterable, Sendable {
    case standingFront = "standing_front"
    case standingThreeQuarter = "standing_three_quarter"
    case walking
    case seated
}
