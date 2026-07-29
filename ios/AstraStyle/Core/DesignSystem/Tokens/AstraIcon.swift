//
//  AstraIcon.swift
//  AstraStyle
//
//  Icon glyph sizing (spec §3 "Iconography", spec §19 accessibility).
//
//  SF Symbols rendered with `.font(.system(size:))` are a design value like any other, and
//  CLAUDE.md forbids hardcoding those. They also share the same Dynamic Type problem as
//  `AstraTypography`: a bare `.system(size:)` does not scale with the user's content size
//  setting, so a 40pt glyph stays 40pt at AX5 while the text beside it triples. Spec §19
//  requires full Dynamic Type support, so glyph sizes go through `@ScaledMetric` too.
//

import SwiftUI

/// Semantic glyph sizes for SF Symbols.
///
/// Sizes are semantic rather than numeric so a symbol's role — not its pixel size — drives the
/// choice. Use `.astraIcon(_:)` to apply one.
public enum AstraIcon: CaseIterable, Hashable, Sendable {
    /// Navigation disclosure indicator (trailing chevron on a tappable row). 13pt.
    case disclosure
    /// Inline with body text: metadata rows, list affordances. 16pt.
    case inline
    /// Standard control glyph: nav bar buttons, the Kyra avatar button. 20pt.
    case control
    /// Emphasised control or card affordance. 24pt.
    case emphasis
    /// Feature-level glyph inside a card or carousel tile. 32pt.
    case feature
    /// Full-screen state illustration: empty, error, permission-denied. 40pt.
    case display

    /// Base (unscaled) point size at the "large" content size category.
    var baseSize: CGFloat {
        switch self {
        case .disclosure: 13
        case .inline: 16
        case .control: 20
        case .emphasis: 24
        case .feature: 32
        case .display: 40
        }
    }

    /// Dynamic Type scaling anchor, matched to the text role the glyph sits alongside.
    var relativeTextStyle: Font.TextStyle {
        switch self {
        case .disclosure: .caption
        case .inline: .body
        case .control: .headline
        case .emphasis: .title3
        case .feature: .title2
        case .display: .largeTitle
        }
    }
}

// MARK: - Dynamic Type-aware application

/// Applies an `AstraIcon` glyph size, scaling with Dynamic Type.
public struct AstraIconModifier: ViewModifier {
    private let weight: Font.Weight
    @ScaledMetric private var scaledSize: CGFloat

    public init(icon: AstraIcon, weight: Font.Weight = .regular) {
        self.weight = weight
        self._scaledSize = ScaledMetric(
            wrappedValue: icon.baseSize,
            relativeTo: icon.relativeTextStyle
        )
    }

    public func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: weight))
    }
}

public extension View {
    /// Applies an Astra glyph size to an SF Symbol, scaling with Dynamic Type.
    ///
    /// ```swift
    /// Image(systemName: "house").astraIcon(.control)
    /// ```
    ///
    /// - Parameters:
    ///   - icon: The semantic glyph size.
    ///   - weight: Symbol weight. Defaults to `.regular`; spec §3 calls for rounded or regular
    ///     weight and warns against cartoon-heavy iconography.
    func astraIcon(_ icon: AstraIcon, weight: Font.Weight = .regular) -> some View {
        modifier(AstraIconModifier(icon: icon, weight: weight))
    }
}
