//
//  OutfitBuilderSlotCard.swift
//  AstraStyle
//
//  One category rail slot on the Outfit builder canvas (spec §6.13). Tap
//  opens the item picker for this category; long-press toggles lock.
//
//  LOCK STATE IS NEVER COLOR-ONLY. Spec §19 forbids encoding meaning by
//  color alone, and a "locked" gold border reads identically to a
//  "selected" one at a glance. The lock icon glyph and the accessibility
//  label/actions below both carry the state independently of the border
//  tint, which is decoration on top of them, not the only signal.
//
//  LONG-PRESS HAS A VOICEOVER EQUIVALENT. A long-press gesture is
//  invisible to VoiceOver and Switch Control — there is nothing to
//  "hold" with a screen reader — so the same toggle is exposed as a named
//  accessibility action, which VoiceOver users reach through the rotor.
//

import SwiftUI

struct OutfitBuilderSlotCard: View {
    let slot: OutfitBuilderSlot
    let onTap: () -> Void
    let onToggleLock: () -> Void

    private static let cardWidth: CGFloat = 132

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                HStack {
                    Text(slot.category.displayName)
                        .astraText(.micro)
                        .foregroundStyle(AstraColor.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: AstraSpacing.xxs)
                    if slot.isLocked {
                        Image(systemName: "lock.fill")
                            .astraIcon(.inline)
                            .foregroundStyle(AstraColor.accentChampagneAccessible)
                            .accessibilityHidden(true)
                    }
                }

                swatch

                Text(slot.item?.name ?? emptyPlaceholder)
                    .astraText(.callout)
                    .foregroundStyle(slot.isFilled ? AstraColor.textPrimary : AstraColor.textMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Self.cardWidth, alignment: .leading)
            .frame(minHeight: AstraSize.minTapTarget)
            .padding(AstraSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .fill(AstraColor.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .strokeBorder(slot.isLocked ? AstraColor.accentChampagneAccessible : AstraColor.divider, lineWidth: slot.isLocked ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .onLongPressGesture(perform: onToggleLock)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text(accessibilityHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(lockActionTitle), onToggleLock)
        .accessibilityIdentifier("outfitBuilder.slot.\(slot.category.rawValue)")
    }

    @ViewBuilder
    private var swatch: some View {
        if let color = slot.item?.primaryColor, let swatchColor = AstraGarmentColor.swatch(for: color).color {
            Circle()
                .fill(swatchColor)
                .frame(width: AstraSpacing.md, height: AstraSpacing.md)
                .overlay(Circle().strokeBorder(AstraColor.divider, lineWidth: 1))
                .accessibilityHidden(true)
        }
    }

    private var emptyPlaceholder: String {
        String(localized: "Tap to add", comment: "Placeholder shown in an empty outfit builder slot")
    }

    private var accessibilityLabel: String {
        var parts = [slot.category.displayName]
        if let item = slot.item {
            parts.append(item.name)
        } else {
            parts.append(String(localized: "Empty", comment: "Accessibility state of an empty outfit builder slot"))
        }
        if slot.isLocked {
            parts.append(String(localized: "Locked", comment: "Accessibility state of a locked outfit builder slot"))
        }
        return parts.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        slot.isFilled
            ? String(localized: "Opens a picker to replace this piece", comment: "VoiceOver hint on a filled outfit builder slot")
            : String(localized: "Opens a picker to choose a piece for this slot", comment: "VoiceOver hint on an empty outfit builder slot")
    }

    private var lockActionTitle: String {
        slot.isLocked
            ? String(localized: "Unlock", comment: "VoiceOver action: unlocks an outfit builder slot")
            : String(localized: "Lock", comment: "VoiceOver action: locks an outfit builder slot so regenerate leaves it alone")
    }
}

#Preview("Slot cards") {
    HStack(spacing: AstraSpacing.sm) {
        OutfitBuilderSlotCard(
            slot: OutfitBuilderSlot(
                category: .top,
                item: ClosetItem(id: UUID(), userID: UUID(), name: "Navy Merino Crewneck", category: .top, primaryColor: "navy"),
                isLocked: true
            ),
            onTap: {},
            onToggleLock: {}
        )
        OutfitBuilderSlotCard(slot: OutfitBuilderSlot(category: .bottom), onTap: {}, onToggleLock: {})
    }
    .padding(AstraSpacing.pagePadding)
    .background(AstraColor.backgroundPrimary)
    .preferredColorScheme(.dark)
}
