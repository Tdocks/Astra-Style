//
//  AstraColor.swift
//  AstraStyle
//
//  Design system color tokens. See /docs/00-master-spec.md §3 and
//  /docs/07-design-system.md for the full token table and contrast analysis.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex & 0xFF0000) >> 16) / 255
        let green = CGFloat((hex & 0x00FF00) >> 8) / 255
        let blue = CGFloat(hex & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif

// MARK: - AstraColorToken

/// Holds a light/dark hex pair for a single semantic color and resolves it to a `Color`
/// that automatically tracks the active `ColorScheme`.
///
/// Rather than scattering `@Environment(\.colorScheme)` reads across every view, each token
/// is backed by a `UIColor` dynamic provider keyed off `UITraitCollection.userInterfaceStyle`.
/// SwiftUI resolves that trait collection at render/draw time, so a single cached `Color`
/// value transparently repaints when the system or in-app appearance changes.
struct AstraColorToken: Sendable {
    /// Packed `0xRRGGBB` value used in dark mode (the app's default appearance).
    let darkHex: UInt32
    /// Packed `0xRRGGBB` value used in light mode.
    let lightHex: UInt32

    init(dark: UInt32, light: UInt32) {
        self.darkHex = dark
        self.lightHex = light
    }

    /// A single symmetric hex value used for both appearances (e.g. a fixed on-accent text color).
    init(fixed hex: UInt32) {
        self.darkHex = hex
        self.lightHex = hex
    }

    var color: Color {
        #if canImport(UIKit)
        let darkHex = darkHex
        let lightHex = lightHex
        return Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
        })
        #else
        return Color(hex: darkHex)
        #endif
    }
}

// MARK: - AstraColor

/// Every color token from the Astra Style design system (spec §3), resolved for the active
/// color scheme automatically. Dark mode is the app's default/native appearance; light mode
/// values are provided for accessibility and system-appearance parity.
///
/// Every hex value below is transcribed directly from spec §3 and is annotated in a trailing
/// comment. See `docs/07-design-system.md` for the full token table and WCAG contrast analysis,
/// including why `accentChampagneAccessible` exists.
public enum AstraColor {

    // MARK: Backgrounds & surfaces

    /// Dark `#0D0D0D` / Light `#F8F5EF`.
    public static var backgroundPrimary: Color {
        AstraColorToken(dark: 0x0D0D0D, light: 0xF8F5EF).color
    }

    /// Dark `#151515` / Light `#EFEAE1`.
    public static var backgroundSecondary: Color {
        AstraColorToken(dark: 0x151515, light: 0xEFEAE1).color
    }

    /// Dark `#1B1B1B` / Light `#FFFFFF`.
    public static var surfaceElevated: Color {
        AstraColorToken(dark: 0x1B1B1B, light: 0xFFFFFF).color
    }

    /// Brand marble texture (spec §3: "Marble is a brand texture, not a universal background").
    ///
    /// The real surface is an asset-based near-black marble image (see
    /// `/tmp/astra/brand/assets/app-icon-marble.jpg` for the visual reference), intended for the
    /// splash screen, app icon, paywall hero, select premium cards, and Kyra transition surfaces
    /// only — never behind dense text.
    ///
    /// Until the marble image asset ships in the asset catalog, this token degrades gracefully to
    /// `backgroundPrimary` so any surface referencing `surfaceMarble` still renders correctly.
    /// Replace the implementation with `Color(uiColor: .init(patternImage: ...))` or an
    /// `Image("MarbleTexture", bundle: .module)`-backed `ImagePaint` once the asset is available;
    /// do not delete this token in the meantime.
    public static var surfaceMarble: Color {
        backgroundPrimary
    }

    // MARK: Text

    /// Dark `#F7F3EA` / Light `#111111`.
    public static var textPrimary: Color {
        AstraColorToken(dark: 0xF7F3EA, light: 0x111111).color
    }

    /// Dark `#B9B3A8` / Light `#56514B`.
    public static var textSecondary: Color {
        AstraColorToken(dark: 0xB9B3A8, light: 0x56514B).color
    }

    /// Dark `#77736C` / Light `#8C867D`.
    public static var textMuted: Color {
        AstraColorToken(dark: 0x77736C, light: 0x8C867D).color
    }

    /// Fixed near-black `#14110A`, used as text/icon color *on top of* a champagne fill
    /// (e.g. the primary button, a selected chip). Champagne is light in both appearances, so a
    /// single dark value gives strong contrast (~9.7:1) regardless of color scheme. See
    /// `docs/07-design-system.md` for the computed ratio.
    public static var textOnAccent: Color {
        AstraColorToken(fixed: 0x14110A).color
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
        AstraColorToken(dark: 0xD7B46A, light: 0xB8914E).color
    }

    /// Dark `#B8944D` (per spec). Light mode pressed value (`#9C7B42`) is not specified by the
    /// spec; it is derived here as ~15% darkened from light-mode `accentChampagne` to preserve a
    /// visible pressed state — flagged in `docs/07-design-system.md` as a spec gap we filled.
    public static var accentChampagnePressed: Color {
        AstraColorToken(dark: 0xB8944D, light: 0x9C7B42).color
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
        AstraColorToken(dark: 0xD7B46A, light: 0x8A6A2E).color
    }

    // MARK: Semantic

    /// Dark `#2A2927` / Light `#DDD6CB`.
    public static var divider: Color {
        AstraColorToken(dark: 0x2A2927, light: 0xDDD6CB).color
    }

    /// Dark `#69745D` / Light value not specified by spec §3; derived by darkening ~20% for
    /// legibility on light backgrounds (`#4E5744`). Always pair with a text descriptor and
    /// numeral — never encode meaning by this color alone (spec §19).
    public static var successOlive: Color {
        AstraColorToken(dark: 0x69745D, light: 0x4E5744).color
    }

    /// Dark `#A98652` / Light value not specified by spec §3; derived by darkening ~20% for
    /// legibility on light backgrounds (`#7E6339`). Always pair with a text descriptor.
    public static var warningAmber: Color {
        AstraColorToken(dark: 0xA98652, light: 0x7E6339).color
    }

    /// Dark `#B65F59` / Light value not specified by spec §3; derived by darkening ~15% for
    /// legibility on light backgrounds (`#9B4F4A`). Always pair with a text descriptor, never
    /// used as the sole indicator of a destructive/error state.
    public static var destructive: Color {
        AstraColorToken(dark: 0xB65F59, light: 0x9B4F4A).color
    }
}
