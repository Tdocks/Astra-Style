//
//  OutfitItemPickerSheet.swift
//  AstraStyle
//
//  Tap-to-replace's picker (spec §6.13). Every closet garment in the
//  tapped slot's category, whether or not it is wearable today — see
//  `OutfitBuilderViewModel.availableItems(for:)`'s own header for why
//  availability is shown rather than used to filter the list.
//

import SwiftUI

struct OutfitItemPickerSheet: View {
    let category: ClothingCategory
    let items: [ClosetItem]
    let currentItemID: UUID?
    let onSelect: (ClosetItem) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(category.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Close", comment: "Dismisses the outfit builder item picker")) {
                            dismiss()
                        }
                    }
                }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AstraSpacing.sm) {
                if currentItemID != nil {
                    clearRow
                }
                ForEach(items) { item in
                    row(for: item)
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }

    private func row(for item: ClosetItem) -> some View {
        Button {
            onSelect(item)
            dismiss()
        } label: {
            HStack(spacing: AstraSpacing.sm) {
                swatch(for: item)
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(item.name)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let subtitle = subtitle(for: item) {
                        Text(subtitle)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
                }
                Spacer(minLength: AstraSpacing.xs)
                if item.id == currentItemID {
                    Image(systemName: "checkmark")
                        .astraIcon(.inline)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: AstraSize.minTapTarget)
            .padding(.horizontal, AstraSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                    .fill(AstraColor.surfaceElevated)
            )
            .contentShape(RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel(for: item)))
        .accessibilityAddTraits(item.id == currentItemID ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("outfitBuilder.picker.item.\(item.id.uuidString.lowercased())")
    }

    private var clearRow: some View {
        Button {
            onClear()
            dismiss()
        } label: {
            Text(String(localized: "Remove from outfit", comment: "Clears the currently filled outfit builder slot"))
                .astraText(.callout)
                .foregroundStyle(AstraColor.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: AstraSize.minTapTarget)
                .padding(.horizontal, AstraSpacing.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("outfitBuilder.picker.clear")
    }

    private var emptyState: some View {
        VStack(spacing: AstraSpacing.md) {
            Image(systemName: "tray")
                .astraIcon(.display)
                .foregroundStyle(AstraColor.textMuted)
                .accessibilityHidden(true)
            Text(String(localized: "Nothing here yet", comment: "Outfit builder picker empty state title"))
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)
            Text(emptyMessage)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AstraSpacing.pagePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }

    private var emptyMessage: String {
        String(
            localized: "Your closet has no \(category.displayName.lowercased()) yet.",
            comment: "Outfit builder picker empty state message, naming the category with nothing in it"
        )
    }

    private func subtitle(for item: ClosetItem) -> String? {
        if let brand = item.brand, !brand.isEmpty { return brand }
        if let subcategory = item.subcategory, !subcategory.isEmpty { return subcategory }
        return nil
    }

    @ViewBuilder
    private func swatch(for item: ClosetItem) -> some View {
        if let color = item.primaryColor, let swatchColor = AstraGarmentColor.swatch(for: color).color {
            Circle()
                .fill(swatchColor)
                .frame(width: AstraSpacing.lg, height: AstraSpacing.lg)
                .overlay(Circle().strokeBorder(AstraColor.divider, lineWidth: 1))
        } else {
            Circle()
                .fill(AstraColor.backgroundSecondary)
                .frame(width: AstraSpacing.lg, height: AstraSpacing.lg)
                .overlay(Circle().strokeBorder(AstraColor.divider, lineWidth: 1))
        }
    }

    private func accessibilityLabel(for item: ClosetItem) -> String {
        var parts = [item.name]
        if let subtitle = subtitle(for: item) { parts.append(subtitle) }
        if item.id == currentItemID {
            parts.append(String(localized: "Selected", comment: "Accessibility state of the currently chosen outfit builder picker item"))
        }
        if !item.isWearableToday {
            parts.append(item.laundryState.displayName)
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Item picker") {
    OutfitItemPickerSheet(
        category: .top,
        items: [
            ClosetItem(id: UUID(), userID: UUID(), name: "Navy Merino Crewneck", brand: "Sunspel", category: .top, primaryColor: "navy")
        ],
        currentItemID: nil,
        onSelect: { _ in },
        onClear: {}
    )
    .preferredColorScheme(.dark)
}
