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

    /// Height of the reference-photo preview on §5.1 step 11.
    ///
    /// A fixed height rather than the image's own aspect ratio, so the
    /// controls beneath it sit in the same place whichever photo was chosen —
    /// a portrait selfie and a landscape snapshot otherwise move the Remove
    /// button by several hundred points. Deliberately NOT scaled by Dynamic
    /// Type: a photograph does not become more legible when the text around
    /// it grows, and growing it would push the controls off an accessibility
    /// -size screen for no gain.
    public static let referencePreviewHeight: CGFloat = 220

    /// The garment today's look is *about*, on Home.
    ///
    /// Fixed heights rather than aspect ratios, and for the same reason as
    /// `referencePreviewHeight`: garment cut-outs have wildly different
    /// proportions — a shoe is wide and short, a coat is tall and narrow —
    /// and letting each one size itself would make the Wear This button
    /// move several hundred points depending on what the scorer picked that
    /// morning. The look holds its shape; the clothes inside it do not.
    public static let lookAnchorHeight: CGFloat = 300

    /// The pieces ranged beside the anchor. Deliberately less than half its
    /// height: an outfit is not a set of equal things, and a layout that
    /// gives the shirt and the watch the same square says otherwise.
    public static let lookSupportingHeight: CGFloat = 120
}
