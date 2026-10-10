//
//  AstraColor.swift
//  AstraStyle
//
//  Design system color tokens. See /docs/00-master-spec.md §3 and
//  /docs/07-design-system.md for the full token table and contrast analysis.
//

import SwiftUI

// MARK: - Color(hex:) convenience

public extension Color {
    /// Creates a color from a packed `0xRRGGBB` integer, e.g. `Color(hex: 0xD7B46A)`.
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex & 0xFF0000) >> 16) / 255
        let green = Double((hex & 0x00FF00) >> 8) / 255
        let blue = Double(hex & 0x0000FF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Creates a color from a hex string such as `"#D7B46A"`, `"D7B46A"`, or `"#D7B46A80"`
    /// (8 hex digits = RGB + alpha). Malformed input safely falls back to opaque black rather
    /// than crashing, since hex strings may originate from remote/CMS content.
    init(hex string: String) {
        var sanitized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }

        guard sanitized.count == 6 || sanitized.count == 8,
              let value = UInt32(sanitized, radix: 16) else {
            self = .black
            return
        }

        if sanitized.count == 8 {
            let alpha = Double(value & 0x0000_00FF) / 255
            self.init(hex: value >> 8, alpha: alpha)
        } else {
            self.init(hex: value)
        }
    }
}

// MARK: - AstraColor

/// Every color token from the Astra Style design system (spec §3), backed by an adaptive
/// Asset Catalog color set. Dark mode is the app's default/native appearance; light mode values
/// are provided for accessibility and system-appearance parity. See `docs/07-design-system.md`
/// for the full token table and WCAG contrast analysis, including why `accentChampagneAccessible`
/// exists.
public enum AstraColor {
    private static func asset(_ name: String) -> Color {
        Color(name, bundle: .main)
    }

    // MARK: Backgrounds & surfaces

    /// Dark `#0D0D0D` / Light `#F8F5EF`.
    public static var backgroundPrimary: Color {
        asset("AstraBackgroundPrimary")
    }

    /// Dark `#151515` / Light `#EFEAE1`.
    public static var backgroundSecondary: Color {
        asset("AstraBackgroundSecondary")
    }

    /// Dark `#1B1B1B` / Light `#FFFFFF`.
    public static var surfaceElevated: Color {
        asset("AstraSurfaceElevated")
    }

    /// Brand marble texture (spec §3: "Marble is a brand texture, not a universal background").
    ///
    /// Near-black base for surfaces that use the separate procedural `AstraMarble` texture
    /// component. Marble is reserved for the splash, paywall hero, select premium cards, and
    /// Kyra transitions; it is never placed behind dense text.
    public static var surfaceMarble: Color {
        asset("AstraSurfaceMarble")
    }

    // MARK: Text

    /// Dark `#F7F3EA` / Light `#111111`.
    public static var textPrimary: Color {
        asset("AstraTextPrimary")
    }

    /// Dark `#B9B3A8` / Light `#56514B`.
    public static var textSecondary: Color {
        asset("AstraTextSecondary")
    }

    /// Dark `#88847C` / Light `#746E66` (revised values from the current contrast review).
    public static var textMuted: Color {
        asset("AstraTextMuted")
    }

    /// Fixed near-black `#14110A`, used as text/icon color *on top of* a champagne fill
    /// (e.g. the primary button, a selected chip). Champagne is light in both appearances, so a
    /// single dark value gives strong contrast (~9.7:1) regardless of color scheme. See
    /// `docs/07-design-system.md` for the computed ratio.
    public static var textOnAccent: Color {
        asset("AstraTextOnAccent")
    }

    // MARK: Accent

    /// Dark `#D7B46A` / Light `#B8914E`.
    ///
    /// Decorative/non-text use only. In light mode this value contrasts only ~2.7–2.9:1 against
    /// `backgroundPrimary`/`surfaceElevated`, which fails WCAG AA for both text (4.5:1) and
    /// large text/non-text UI (3:1). Use it for fills that sit *behind* `textOnAccent`, icon
    /// tints paired with a text label, thin rules/dividers, and dark-mode text — never as a
    /// light-mode text or border color. See `docs/07-design-system.md §Accessibility`.
    public static var accentChampagne: Color {
        asset("AstraAccentChampagne")
    }

    /// Dark `#B8944D` (per spec). Light mode pressed value (`#9C7B42`) is not specified by the
    /// spec; it is derived here as ~15% darkened from light-mode `accentChampagne` to preserve a
    /// visible pressed state — flagged in `docs/07-design-system.md` as a spec gap we filled.
    public static var accentChampagnePressed: Color {
        asset("AstraAccentChampagnePressed")
    }

    /// High-contrast champagne alternative required by spec §19 ("High-contrast alternative for
    /// champagne text"). Dark mode reuses `accentChampagne` (`#D7B46A`, already ~9.8:1 on
    /// `backgroundPrimary`). Light mode uses a darkened gold, `#8A6A2E`, chosen because it clears
    /// 4.5:1 against both `backgroundPrimary` (light) and `surfaceElevated` (light) — see the
    /// computed ratios in `docs/07-design-system.md`.
    ///
    /// Use this token — not `accentChampagne` — anywhere champagne meaning must be conveyed as
    /// *text or a border/stroke* (links, selected states, secondary/tertiary button labels,
    /// eyebrow labels, chip borders).
    public static var accentChampagneAccessible: Color {
        asset("AstraAccentChampagneAccessible")
    }

    // MARK: Semantic

    /// Dark `#2A2927` / Light `#DDD6CB`.
    public static var divider: Color {
        asset("AstraDivider")
    }

    /// Dark `#69745D` / Light value not specified by spec §3; derived by darkening ~20% for
    /// legibility on light backgrounds (`#4E5744`). Always pair with a text descriptor and
    /// numeral — never encode meaning by this color alone (spec §19).
    public static var successOlive: Color {
        asset("AstraSuccessOlive")
    }

    /// Dark `#A98652` / Light value not specified by spec §3; derived by darkening ~20% for
    /// legibility on light backgrounds (`#7E6339`). Always pair with a text descriptor.
    public static var warningAmber: Color {
        asset("AstraWarningAmber")
    }

    /// Dark `#B65F59` / Light value not specified by spec §3; derived by darkening ~15% for
    /// legibility on light backgrounds (`#9B4F4A`). Always pair with a text descriptor, never
    /// used as the sole indicator of a destructive/error state.
    public static var destructive: Color {
        asset("AstraDestructive")
    }
}
