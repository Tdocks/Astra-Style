//
//  ScannerReviewFormView.swift
//  AstraStyle
//
//  Editable attribute form for the scan-review screen (P3-SCAN-09).
//  Split from `ScannerReviewView` so the host view stays under
//  SwiftLint's `type_body_length` ceiling.
//

import SwiftUI

struct ScannerReviewFormView: View {
    @Bindable var viewModel: ScannerReviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraTextField(
                String(localized: "Name", comment: "Scan review name"),
                text: $viewModel.name,
                placeholder: String(localized: "e.g. Navy Crewneck", comment: "Scan review name placeholder"),
                footnote: viewModel.lowConfidenceFootnote(.name),
                isRequired: true
            )
            .accessibilityIdentifier("scanner.review.name")

            AstraTextField(
                String(localized: "Brand", comment: "Scan review brand"),
                text: $viewModel.brand,
                placeholder: String(localized: "Optional", comment: "Optional field placeholder"),
                footnote: viewModel.lowConfidenceFootnote(.brand)
            )
            .accessibilityIdentifier("scanner.review.brand")

            categoryPicker

            AstraTextField(
                String(localized: "Subtype", comment: "Scan review subcategory"),
                text: $viewModel.subcategory,
                footnote: viewModel.lowConfidenceFootnote(.subcategory)
            )

            AstraTextField(
                String(localized: "Primary colour", comment: "Scan review primary color"),
                text: $viewModel.primaryColor,
                footnote: viewModel.lowConfidenceFootnote(.primaryColor)
            )

            AstraTextField(
                String(localized: "Secondary colours", comment: "Scan review secondary colors"),
                text: $viewModel.secondaryColorsText,
                placeholder: String(localized: "Comma-separated", comment: "List field hint"),
                footnote: viewModel.lowConfidenceFootnote(.secondaryColors)
            )

            AstraTextField(
                String(localized: "Material", comment: "Scan review material"),
                text: $viewModel.materialText,
                placeholder: String(localized: "Comma-separated", comment: "List field hint"),
                footnote: viewModel.lowConfidenceFootnote(.material)
            )

            AstraTextField(
                String(localized: "Size", comment: "Scan review size"),
                text: $viewModel.size,
                footnote: viewModel.lowConfidenceFootnote(.size)
            )

            patternPicker
            fitPicker
            conditionPicker
            seasonalityPicker
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(String(localized: "Category", comment: "Scan review category"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
            if viewModel.isLowConfidence(.category) {
                Text(viewModel.lowConfidenceFootnote(.category) ?? "")
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.warningAmber)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AstraSpacing.sm) {
                    ForEach(ClothingCategory.allCases, id: \.self) { option in
                        AstraChip(option.displayName, isSelected: viewModel.category == option) {
                            viewModel.category = option
                            AstraHaptics.selection()
                        }
                    }
                }
            }
            .accessibilityIdentifier("scanner.review.category")
        }
    }

    private var patternPicker: some View {
        optionalEnumChips(EnumChipConfig(
            title: String(localized: "Pattern", comment: "Scan review pattern"),
            selection: $viewModel.pattern,
            options: GarmentPattern.allCases,
            titleFor: { $0.displayName },
            lowConfidence: viewModel.isLowConfidence(.pattern),
            footnote: viewModel.lowConfidenceFootnote(.pattern)
        ))
    }

    private var fitPicker: some View {
        optionalEnumChips(EnumChipConfig(
            title: String(localized: "Fit", comment: "Scan review fit"),
            selection: $viewModel.fit,
            options: ItemFit.allCases,
            titleFor: { $0.displayName },
            lowConfidence: viewModel.isLowConfidence(.fit),
            footnote: viewModel.lowConfidenceFootnote(.fit)
        ))
    }

    private var conditionPicker: some View {
        optionalEnumChips(EnumChipConfig(
            title: String(localized: "Condition", comment: "Scan review condition"),
            selection: $viewModel.condition,
            options: ItemCondition.allCases,
            titleFor: { $0.displayName },
            lowConfidence: viewModel.isLowConfidence(.condition),
            footnote: viewModel.lowConfidenceFootnote(.condition)
        ))
    }

    private var seasonalityPicker: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(String(localized: "Season", comment: "Scan review seasonality"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
            if viewModel.isLowConfidence(.seasonality) {
                Text(viewModel.lowConfidenceFootnote(.seasonality) ?? "")
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.warningAmber)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AstraSpacing.sm) {
                    ForEach(Season.allCases, id: \.self) { season in
                        AstraChip(season.displayName, isSelected: viewModel.seasonality.contains(season)) {
                            if viewModel.seasonality.contains(season) {
                                viewModel.seasonality.remove(season)
                            } else {
                                viewModel.seasonality.insert(season)
                            }
                            AstraHaptics.selection()
                        }
                    }
                }
            }
        }
    }

    private struct EnumChipConfig<Value: Hashable> {
        let title: String
        let selection: Binding<Value?>
        let options: [Value]
        let titleFor: (Value) -> String
        let lowConfidence: Bool
        let footnote: String?
    }

    private func optionalEnumChips<Value: Hashable>(_ config: EnumChipConfig<Value>) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(config.title)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
            if config.lowConfidence, let footnote = config.footnote, !footnote.isEmpty {
                Text(footnote)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.warningAmber)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AstraSpacing.sm) {
                    ForEach(config.options, id: \.self) { option in
                        AstraChip(config.titleFor(option), isSelected: config.selection.wrappedValue == option) {
                            config.selection.wrappedValue =
                                config.selection.wrappedValue == option ? nil : option
                            AstraHaptics.selection()
                        }
                    }
                }
            }
        }
    }
}
