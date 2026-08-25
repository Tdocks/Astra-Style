//
//  AstraChip.swift
//  AstraStyle
//
//  Capsule filter/tag chip (spec §3: "Compact chip radius: capsule"; iconography rule "Gold
//  indicates active state; bone/gray indicates inactive").
//

import SwiftUI

/// A capsule-shaped filter or tag chip with a selected/unselected state.
///
/// Selected state is not conveyed by color alone: the fill vs. outline treatment and an
/// optional checkmark glyph both change too, so the state reads correctly for users who can't
/// distinguish the gold/bone color difference.
public struct AstraChip: View {
    private let title: String
    private let systemImage: String?
    private let swatches: [Color]
    private let isSelected: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - title: The chip's label (e.g. a category or color name).
    ///   - systemImage: Optional SF Symbol shown before the label.
    ///   - swatches: Optional colour dots drawn before the label. Always paired
    ///     with `title` so colour is never the only cue (spec §19). Light
    ///     swatches are stroked so they keep an edge on a light background.
    ///   - isSelected: Whether the chip is in the active/selected (gold) state.
    ///   - action: Invoked on tap, typically toggling `isSelected` upstream.
    public init(
        _ title: String,
        systemImage: String? = nil,
        swatches: [Color] = [],
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.swatches = swatches
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: AstraSpacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                }
                if !swatches.isEmpty {
                    HStack(spacing: AstraSpacing.xxs) {
                        ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                            Circle()
                                .fill(color)
                                .frame(width: AstraSpacing.md, height: AstraSpacing.md)
                                .overlay(
                                    Circle().strokeBorder(AstraColor.divider, lineWidth: 1)
                                )
                                .accessibilityHidden(true)
                        }
                    }
                }
                Text(title)
                    .astraText(.caption)
                    // Wrap onto a second line rather than truncating or running
                    // past the chip's edge. At accessibility sizes a label like
                    // "Good jeans, decent shirt" is wider than the whole screen,
                    // and without this it rendered as "Good jeans, decent shi"
                    // with the rest off the right edge.
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                }
            }
            .foregroundStyle(isSelected ? AstraColor.textOnAccent : AstraColor.textSecondary)
            .padding(.horizontal, AstraSpacing.md)
            // Vertical padding matters once the label can wrap: minHeight alone
            // holds a single line off the capsule's edge by luck, not by design,
            // and two lines would touch the stroke top and bottom.
            .padding(.vertical, AstraSpacing.xs)
            .frame(minHeight: AstraSize.minTapTarget)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AstraColor.accentChampagne : AstraColor.backgroundSecondary)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : AstraColor.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .astraAnimation(AstraMotion.standard, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
    }
}
