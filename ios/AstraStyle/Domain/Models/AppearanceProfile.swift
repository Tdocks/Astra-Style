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
//    • Skin undertone drives which palette Kyra recommends against — warm and
//      cool undertones flatter different neutrals. This is the only field here
//      that changes advice on its own.
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
        skinUndertone: String? = nil,
        hairColor: String? = nil,
        eyeColor: String? = nil,
        facialHair: String? = nil,
        wearsGlasses: Bool? = nil,
        tattoosVisible: Bool? = nil,
        referenceSelfiePaths: [String] = []
    ) {
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
        skinUndertone == nil && hairColor == nil && eyeColor == nil
            && facialHair == nil && wearsGlasses == nil && tattoosVisible == nil
            && referenceSelfiePaths.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case skinUndertone = "skin_undertone"
        case hairColor = "hair_color"
        case eyeColor = "eye_color"
        case facialHair = "facial_hair"
        case wearsGlasses = "wears_glasses"
        case tattoosVisible = "tattoos_visible"
        case referenceSelfiePaths = "reference_selfie_paths"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        skinUndertone = try c.decodeIfPresent(String.self, forKey: .skinUndertone)
        hairColor = try c.decodeIfPresent(String.self, forKey: .hairColor)
        eyeColor = try c.decodeIfPresent(String.self, forKey: .eyeColor)
        facialHair = try c.decodeIfPresent(String.self, forKey: .facialHair)
        wearsGlasses = try c.decodeIfPresent(Bool.self, forKey: .wearsGlasses)
        tattoosVisible = try c.decodeIfPresent(Bool.self, forKey: .tattoosVisible)
        // Defaulted rather than optional: an absent key and an empty list mean
        // the same thing to every caller, and a `[String]?` would make every
        // read site handle a distinction that does not exist.
        referenceSelfiePaths = try c.decodeIfPresent([String].self, forKey: .referenceSelfiePaths) ?? []
    }
}

// MARK: - Offered options

/// The shortcut vocabulary the §6.7 screen offers.
///
/// Deliberately short. A long list of hair colors reads as a form to be
/// completed; six reads as a suggestion. Anything not listed is still valid —
/// these values are only what the picker writes.
public enum AppearanceOptions {
    /// Ordered warm → neutral → cool, which is how the palette rules read them.
    public static let skinUndertones = ["Warm", "Neutral", "Cool", "Olive"]

    public static let hairColors = [
        "Black", "Dark brown", "Light brown", "Blonde", "Red", "Gray", "Salt and pepper", "None"
    ]

    public static let eyeColors = ["Brown", "Hazel", "Green", "Blue", "Gray"]

    public static let facialHairStyles = [
        "Clean shaven", "Stubble", "Moustache", "Short beard", "Full beard"
    ]
}
