//
//  AstraTypography.swift
//  AstraStyle
//
//  Editorial type scale (spec §3). Serif styles map to New York via
//  `.system(size:design:.serif)`; UI text uses SF Pro via `.system(size:design:.default)`.
//

import SwiftUI

/// The nine editorial text styles from spec §3, with everything needed to render and to scale
/// correctly with Dynamic Type.
public enum AstraTypography: CaseIterable, Hashable, Sendable {
    case displayXL
    case displayL
    case title1
    case title2
    case headline
    case body
    case callout
    case caption
    case micro

    /// Base (unscaled, "large" content size category) point size, per spec §3.
    var baseSize: CGFloat {
        switch self {
        case .displayXL: 42
        case .displayL: 34
        case .title1: 28
        case .title2: 22
        case .headline: 17
        case .body: 16
        case .callout: 15
        case .caption: 12
        case .micro: 10
        }
    }

    var design: Font.Design {
        switch self {
        case .displayXL, .displayL, .title1, .title2: .serif
        case .headline, .body, .callout, .caption, .micro: .default
        }
    }

    var weight: Font.Weight {
        switch self {
        case .displayXL, .displayL: .semibold
        // Spec gives no explicit weight for title1/title2; regular is the editorial-serif default.
        case .title1, .title2: .regular
        case .headline: .semibold
        case .body, .callout: .regular
        case .caption: .regular
        // Spec gives no explicit weight for micro; semibold is used for legibility at 10pt
        // uppercase tracked text — a design decision documented in docs/07-design-system.md.
        case .micro: .semibold
        }
    }

    /// The closest built-in Dynamic Type text style, used as the scaling anchor so this token
    /// grows/shrinks along the same curve iOS uses for that role.
    var relativeTextStyle: Font.TextStyle {
        switch self {
        case .displayXL, .displayL: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .caption: .caption
        case .micro: .caption2
        }
    }

    /// Tracking (letter-spacing) in points. Only `micro` specifies tracking in spec §3 (1.5).
    var tracking: CGFloat {
        switch self {
        case .micro: 1.5
        default: 0
        }
    }

    /// `micro` is uppercase per spec §3 ("10 pt sans, uppercase, tracking 1.5").
    var isUppercase: Bool {
        self == .micro
    }
}

// MARK: - Dynamic Type-aware application

/// Applies an `AstraTypography` style to any view, scaling the base point size with the user's
/// Dynamic Type setting.
///
/// `Font.system(size:)` alone does **not** scale with Dynamic Type — only `Font.system(.body)`-style
/// semantic fonts, or an explicit `UIFontMetrics`/`@ScaledMetric` scaled size, do. Spec §19 requires
/// "Full Dynamic Type support," so this modifier drives the point size through `@ScaledMetric`,
/// anchored to the closest matching built-in text style, before handing it to
/// `.system(size:weight:design:)`.
public struct AstraTextStyleModifier: ViewModifier {
    private let style: AstraTypography
    @ScaledMetric private var scaledSize: CGFloat

    public init(style: AstraTypography) {
        self.style = style
        self._scaledSize = ScaledMetric(wrappedValue: style.baseSize, relativeTo: style.relativeTextStyle)
    }

    public func body(content: Content) -> some View {
        content
            .font(.system(size: scaledSize, weight: style.weight, design: style.design))
            .tracking(style.tracking)
            .textCase(style.isUppercase ? .uppercase : nil)
    }
}

public extension View {
    /// Applies an Astra editorial text style (font, tracking, and case) with Dynamic Type scaling.
    ///
    /// ```swift
    /// Text("Good morning, Theo.").astraText(.displayL)
    /// ```
    func astraText(_ style: AstraTypography) -> some View {
        modifier(AstraTextStyleModifier(style: style))
    }
}

public extension Text {
    /// Convenience factory that builds and styles a `Text` in one call.
    ///
    /// ```swift
    /// Text.astra("Visual Estimate", style: .micro)
    /// ```
    static func astra(_ content: String, style: AstraTypography) -> some View {
        Text(content).astraText(style)
    }
}
