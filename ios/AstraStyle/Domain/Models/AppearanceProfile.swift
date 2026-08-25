//
//  AppearanceProfile.swift
//  AstraStyle
//
//  Spec §6.7 — the optional appearance attributes, stored as the `appearance`
//  jsonb column on `body_profiles`.
//
//  A jsonb blob rather than six nullable columns, matching the migration's
//  stated reasoning: every field is optional, free-form and user-omittable by
//  design. That also means `check_column_drift.py` cannot police these keys —
//  jsonb has no columns to compare against — so the key names are asserted in
//  `AppearanceProfileTests` instead. Without that, a rename here would silently
//  orphan every previously-written value, which is precisely the failure
//  `BodyProfile`'s header describes.
//
//  WHY EACH FIELD EXISTS, because §6.7 requires the app to explain that and the
//  answer had better be true:
//
//    • Skin tone (depth) is how light or deep the complexion is. Without it
//      every palette rule quietly assumes a light face, which is why a
//      Warm/Cool chip row alone reads as a white-skin instrument.
//    • Skin undertone drives which neutrals Kyra recommends — warm, cool,
//      olive. It is independent of depth: a deep complexion is still warm
//      or cool. The picker shows each temperature on a lighter and a
//      deeper swatch so the words are not the only cue (spec §19).
//    • Hair and eye color refine contrast level, which decides how far apart a
//      recommended outfit's light and dark values should sit.
//    • Facial hair and glasses affect neckline and collar suggestions, and
//      matter for Style Studio reference images (§13) — a generated image
//      without a user's beard does not read as him.
//    • Tattoo visibility affects sleeve-length suggestions ONLY when the user
//      says it should. It is never used to suggest covering anything up.
//
//  Every field is a plain String rather than an enum. The vocabulary here is
//  genuinely open — "auburn", "salt and pepper" and "graying at the temples"
//  are all real answers — and the screen offers a controlled list only as a
//  shortcut, not as a constraint. Values written by the picker come from
//  `AppearanceOptions` so the common cases stay consistent.
//

import Foundation

public struct AppearanceProfile: Codable, Hashable, Sendable {
    public var skinTone: String?
    public var skinUndertone: String?
    public var hairColor: String?
    public var eyeColor: String?
    public var facialHair: String?
    public var wearsGlasses: Bool?
    public var tattoosVisible: Bool?
    /// Storage paths under `users/{user_id}/references/`, never the image bytes.
    ///
    /// Kept as paths for the same reason the migration comment says so: the
    /// images are consent-gated (§29) and must be deletable by deleting the
    /// object, without rewriting rows that happen to embed them.
    public var referenceSelfiePaths: [String]

    public init(
        skinTone: String? = nil,
        skinUndertone: String? = nil,
        hairColor: String? = nil,
        eyeColor: String? = nil,
        facialHair: String? = nil,
        wearsGlasses: Bool? = nil,
        tattoosVisible: Bool? = nil,
        referenceSelfiePaths: [String] = []
    ) {
        self.skinTone = skinTone
        self.skinUndertone = skinUndertone
        self.hairColor = hairColor
        self.eyeColor = eyeColor
        self.facialHair = facialHair
        self.wearsGlasses = wearsGlasses
        self.tattoosVisible = tattoosVisible
        self.referenceSelfiePaths = referenceSelfiePaths
    }

    /// True when the user answered nothing at all.
    ///
    /// Used to decide whether to write `{}` rather than a blob of nulls, so a
    /// skipped step is distinguishable in the database from an answered one
    /// where every answer happened to be cleared.
    public var isEmpty: Bool {
        skinTone == nil && skinUndertone == nil && hairColor == nil && eyeColor == nil
            && facialHair == nil && wearsGlasses == nil && tattoosVisible == nil
            && referenceSelfiePaths.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case skinTone = "skin_tone"
        case skinUndertone = "skin_undertone"
        case hairColor = "hair_color"
        case eyeColor = "eye_color"
        case facialHair = "facial_hair"
        case wearsGlasses = "wears_glasses"
        case tattoosVisible = "tattoos_visible"
        case referenceSelfiePaths = "reference_selfie_paths"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skinTone = try container.decodeIfPresent(String.self, forKey: .skinTone)
        skinUndertone = try container.decodeIfPresent(String.self, forKey: .skinUndertone)
        hairColor = try container.decodeIfPresent(String.self, forKey: .hairColor)
        eyeColor = try container.decodeIfPresent(String.self, forKey: .eyeColor)
        facialHair = try container.decodeIfPresent(String.self, forKey: .facialHair)
        wearsGlasses = try container.decodeIfPresent(Bool.self, forKey: .wearsGlasses)
        tattoosVisible = try container.decodeIfPresent(Bool.self, forKey: .tattoosVisible)
        // Defaulted rather than optional: an absent key and an empty list mean
        // the same thing to every caller, and a `[String]?` would make every
        // read site handle a distinction that does not exist.
        referenceSelfiePaths = try container.decodeIfPresent([String].self, forKey: .referenceSelfiePaths) ?? []
    }
}

// MARK: - Offered options

/// One complexion or undertone the §6.7 screen offers, with the hexes
/// drawn next to the label so the word is never the only cue (spec §19).
public struct AppearanceSwatchChoice: Hashable, Sendable, Identifiable {
    public var label: String
    /// Packed `0xRRGGBB`. Undertone choices carry three — the same temperature
    /// on a lighter, mid, and deeper complexion — so the row does not only
    /// illustrate the temperature on fair skin.
    public var hexes: [UInt32]
    /// Depth grouping on the picker (`Fair to light`, `Medium`, `Deep`).
    /// Undertone and hair/eye chips leave this nil.
    public var section: String?
    public var id: String { label }

    public init(label: String, hexes: [UInt32], section: String? = nil) {
        self.label = label
        self.hexes = hexes
        self.section = section
    }
}

/// The shortcut vocabulary the §6.7 screen offers.
///
/// Deliberately short. A long list of hair colors reads as a form to be
/// completed; six reads as a suggestion. Anything not listed is still valid —
/// these values are only what the picker writes.
public enum AppearanceOptions {
    /// Light → deepest, grouped Fair to light / Medium / Deep so a deeper
    /// complexion is its own section, not leftover chips after a fair cluster.
    /// Labels are depth, not ethnicity. Hexes follow a Monk-inspired value
    /// scale (golden-neutral at the light end, red-brown at the deep end)
    /// rather than a pink-peach European range.
    public static let skinTones: [AppearanceSwatchChoice] = [
        AppearanceSwatchChoice(label: "Light", hexes: [0xF1D0B0], section: "Fair to light"),
        AppearanceSwatchChoice(label: "Medium light", hexes: [0xE0B089], section: "Fair to light"),
        AppearanceSwatchChoice(label: "Medium", hexes: [0xC68A5A], section: "Medium"),
        AppearanceSwatchChoice(label: "Medium deep", hexes: [0x8D5A36], section: "Medium"),
        AppearanceSwatchChoice(label: "Deep", hexes: [0x5A3318], section: "Deep"),
        AppearanceSwatchChoice(label: "Deepest", hexes: [0x271610], section: "Deep"),
    ]

    /// Warm → olive. Each triple is the same undertone on a lighter, mid,
    /// and deeper complexion; stored values stay the historic strings so
    /// existing `appearance` jsonb rows keep matching.
    public static let skinUndertoneChoices: [AppearanceSwatchChoice] = [
        AppearanceSwatchChoice(label: "Warm", hexes: [0xE8C4A0, 0xC68654, 0x7A4A28]),
        AppearanceSwatchChoice(label: "Neutral", hexes: [0xD7C2B0, 0xA0806C, 0x614A3C]),
        AppearanceSwatchChoice(label: "Cool", hexes: [0xE0B8B4, 0xA07070, 0x5A3D3A]),
        AppearanceSwatchChoice(label: "Olive", hexes: [0xC4B88A, 0x8A8458, 0x4F4630]),
    ]

    /// Ordered warm → olive, which is how the palette rules read them.
    public static let skinUndertones = skinUndertoneChoices.map(\.label)

    public static let hairColors = [
        "Black", "Dark brown", "Light brown", "Blonde", "Red", "Gray", "Salt and pepper", "None"
    ]

    public static let eyeColors = ["Brown", "Hazel", "Green", "Blue", "Gray"]

    public static let facialHairStyles = [
        "Clean shaven", "Stubble", "Mustache", "Short beard", "Full beard"
    ]
}
