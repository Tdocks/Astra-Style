//
//  AstraGarmentColor.swift
//  AstraStyle
//
//  Swatches for colours that arrive as WORDS from the server.
//
//  Every other colour in this app is a semantic design token: `textPrimary`
//  means "the colour text is", and the token decides what that is in each
//  appearance. This file is the one place that is not true, because the
//  §6.10 palette is content — `style_dna.palette.preferred_colors` is a list
//  of strings like "tobacco brown" written by
//  `supabase/functions/style-dna/identityPlaybook.ts`, and a screen that only
//  printed those words would be a stylist describing a palette without
//  showing it.
//
//  WHY THE VALUES LIVE HERE RATHER THAN INLINE IN THE VIEW. CLAUDE.md's rule
//  is that a colour literal in a view is a bug, and the reason it gives holds
//  exactly as much for these: a swatch guessed at the call site drifts the
//  moment a second screen shows the same palette (the Profile tab's Style DNA
//  section will), and there would be no single place to retune "olive" when
//  someone decides it reads too yellow. So this is a token file like the
//  others — it just happens to be keyed by an English word instead of by a
//  role.
//
//  WHY AN UNKNOWN NAME PRODUCES NO SWATCH RATHER THAN A GUESS. The server's
//  palette vocabulary is content and will grow; a build that has never heard
//  of "burnt sienna" must not paint a rectangle it invented and label it with
//  the user's palette. `AstraSwatch.hex == nil` is the honest answer, and the
//  view renders those name-only — the word is always shown either way, which
//  is also what spec §19 requires (colour is never the sole carrier of
//  meaning).
//
//  THESE ARE NOT APPEARANCE-PAIRED. A swatch for "navy" is a picture of navy
//  cloth, not a UI surface, so it does not flip between light and dark mode —
//  inverting it would be showing the user a different colour and calling it
//  the same one. Legibility against the page is handled by the view, which
//  strokes every swatch with `AstraColor.divider` so a bone or bright-white
//  chip still has an edge on the light background.
//

import SwiftUI

/// One entry of a Style DNA palette: the server's own word for a colour, and
/// the swatch to draw beside it if this build knows one.
public struct AstraSwatch: Hashable, Sendable, Identifiable {
    /// The colour name exactly as the server wrote it. Always displayed.
    public let name: String
    /// Packed `0xRRGGBB`, or `nil` when this build has no swatch for the name.
    public let hex: UInt32?

    public var id: String { name }

    /// `nil` when there is no swatch to draw — the view shows the name alone.
    public var color: Color? {
        hex.map { Color(hex: $0) }
    }

    public init(name: String, hex: UInt32?) {
        self.name = name
        self.hex = hex
    }
}

/// Resolves a palette colour name to a swatch.
public enum AstraGarmentColor {

    /// The swatch for a colour name, or a name-only swatch when unknown.
    ///
    /// Resolution is two steps, and the second one is what keeps this table
    /// small enough to stay maintained: an exact match first, then the LAST
    /// word of the name. English colour names are head-final — "tobacco
    /// brown" is a brown, "faded indigo" is an indigo — so the final word is
    /// the colour and everything before it is a modifier. That also makes the
    /// right thing happen for the server's category words: "neon brights" and
    /// "pale pastels" are not colours, their final words are not in the
    /// table, and they come back name-only, which is exactly how they should
    /// render.
    public static func swatch(for name: String) -> AstraSwatch {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let hex = table[key] {
            return AstraSwatch(name: name, hex: hex)
        }
        if let head = key.split(separator: " ").last, let hex = table[String(head)] {
            return AstraSwatch(name: name, hex: hex)
        }
        return AstraSwatch(name: name, hex: nil)
    }

    /// Maps a whole palette in order, preserving duplicates and casing.
    public static func swatches(for names: [String]) -> [AstraSwatch] {
        names.map(swatch(for:))
    }

    // The vocabulary `identityPlaybook.ts` actually emits across its ten
    // identities, plus the bare head words every modifier form falls back to.
    // Multi-word entries are here only where the modifier genuinely changes
    // the colour ("cold silver grey" is not grey); anything the head-word rule
    // already gets right is deliberately absent rather than duplicated.
    private static let table: [String: UInt32] = [
        // Neutrals — dark
        "black": 0x111111,
        "flat black": 0x141414,
        "heavy black": 0x0E0E0E,
        "charcoal": 0x36373A,
        "cold charcoal": 0x33373C,
        // Neutrals — mid
        "grey": 0x8A8A8A,
        "gray": 0x8A8A8A,
        "mid grey": 0x8C8C8C,
        "stone grey": 0x9A958C,
        "washed grey": 0xA6A29B,
        "cold silver grey": 0xB4B8BC,
        "corporate mid grey": 0x86888C,
        "mid business grey": 0x86888C,
        "stone": 0xC9C1B2,
        // Neutrals — light
        "white": 0xF2F0EB,
        "bright white": 0xFAFAF8,
        "bone": 0xEDE6D8,
        "cream": 0xF0E7D3,
        "ivory": 0xF4EEDF,
        "ecru": 0xE6DCC6,
        "oatmeal": 0xD8CDB6,
        "sand": 0xD9C9A8,
        // Blues
        "navy": 0x1F2A44,
        "ink blue": 0x232E45,
        "blue": 0x33507F,
        "indigo": 0x33406B,
        "faded indigo": 0x5A6B8C,
        "cobalt": 0x2B4FA2,
        "slate blue": 0x5A6B80,
        "sky blue": 0x8FB4D6,
        "pale blue": 0xB9CFE2,
        // Greens
        "green": 0x3B5A40,
        "olive": 0x5A5F3C,
        "deep olive": 0x454A2E,
        "faded olive": 0x757A5C,
        "moss": 0x5E6B4A,
        "sage": 0x9AA48C,
        "forest green": 0x2C4433,
        "hunter green": 0x2A4331,
        "deep green": 0x27412F,
        // Browns and tans
        "brown": 0x5C4433,
        "soft brown": 0x7A5F49,
        "tobacco brown": 0x6B4A2F,
        "camel": 0xC19A6B,
        "tan": 0xC49A6C,
        "khaki": 0xA89A73,
        // Reds
        "red": 0x9B3A2E,
        "barn red": 0x8E2B22,
        "burgundy": 0x5E2233,
        "oxblood": 0x4A1B23,
        "rust": 0xA4552B,
        "terracotta": 0xB0603C,
        // Yellows
        "yellow": 0xD6B23C,
        "acid yellow": 0xD3DC22,
        "mustard": 0xC9A227,
        "saffron": 0xD8A128,
        "lemon": 0xE8D24A,
        // Purples
        "plum": 0x5A3752
    ]
}
