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
    private let isSelected: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - title: The chip's label (e.g. a category or color name).
    ///   - systemImage: Optional SF Symbol shown before the label.
    ///   - isSelected: Whether the chip is in the active/selected (gold) state.
    ///   - action: Invoked on tap, typically toggling `isSelected` upstream.
    public init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
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
                Text(title)
                    .astraText(.caption)
                if isSelected {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                }
            }
            .foregroundStyle(isSelected ? AstraColor.textOnAccent : AstraColor.textSecondary)
            .padding(.horizontal, AstraSpacing.md)
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
