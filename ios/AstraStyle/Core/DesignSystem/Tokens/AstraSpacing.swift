//
//  AstraSpacing.swift
//  AstraStyle
//
//  Layout constants (spec §3 "Layout"): 4pt base spacing unit, page padding, corner radii,
//  and minimum tap target. Every layout constant used across the design system and features
//  should come from here rather than being hard-coded inline.
//

import CoreGraphics

/// 4pt-base spacing scale. Use these instead of raw point values for padding, stack spacing,
/// and gaps so the whole app stays on a consistent rhythm.
public enum AstraSpacing {
    /// The base unit itself: 4 pt.
    public static let unit: CGFloat = 4

    /// 4 pt — hairline gaps (e.g. between an icon and a tightly-set label).
    public static let xxs: CGFloat = unit * 1
    /// 8 pt — tight internal spacing.
    public static let xs: CGFloat = unit * 2
    /// 12 pt — compact spacing (e.g. within a chip or list row).
    public static let sm: CGFloat = unit * 3
    /// 16 pt — default internal component spacing.
    public static let md: CGFloat = unit * 4
    /// 20 pt — standard page padding, per spec §3.
    public static let lg: CGFloat = unit * 5
    /// 24 pt — section spacing.
    public static let xl: CGFloat = unit * 6
    /// 32 pt — spacing between major page sections.
    public static let xxl: CGFloat = unit * 8
    /// 40 pt — large hero-level spacing.
    public static let xxxl: CGFloat = unit * 10

    /// Standard page padding: 20 pt, per spec §3. Alias of `lg` kept for call-site clarity.
    public static let pagePadding: CGFloat = lg

    /// Card corner radius: 18 pt, per spec §3. Convenience alias of `AstraRadius.card` kept on
    /// `AstraSpacing` since that's the single layout-constants bullet the spec groups it under.
    public static let cardRadius: CGFloat = AstraRadius.card

    /// Button corner radius: 14 pt, per spec §3. Convenience alias of `AstraRadius.button`.
    public static let buttonRadius: CGFloat = AstraRadius.button

    /// Minimum tap target: 44 pt, per spec §3/§19. Convenience alias of `AstraSize.minTapTarget`.
    public static let minTapTarget: CGFloat = AstraSize.minTapTarget
}

/// Corner radii, per spec §3.
public enum AstraRadius {
    /// Card corner radius: 18 pt.
    public static let card: CGFloat = 18
    /// Button corner radius: 14 pt.
    public static let button: CGFloat = 14
    /// Compact chip radius: capsule (i.e. fully rounded — use `Capsule()`, not a fixed value).
    public static let chip: CGFloat = .infinity
    /// Small element radius: 8 pt. Not itemized separately in spec §3 (which only names card and
    /// button radii); used for small decorative surfaces smaller than a card or button — e.g.
    /// skeleton-loading placeholder blocks — that would otherwise round to `card`/`button` at a
    /// visually mismatched scale.
    public static let small: CGFloat = 8
}

/// Control sizing constants, per spec §3 and §19 (Accessibility).
public enum AstraSize {
    /// Minimum tap target: 44 × 44 pt.
    public static let minTapTarget: CGFloat = 44
}
