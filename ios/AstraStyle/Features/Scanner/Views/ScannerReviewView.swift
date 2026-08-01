//
//  ScannerReviewView.swift
//  AstraStyle
//
//  Spec §6.16 / §12 review screen (P3-SCAN-09): editable suggestions with
//  low-confidence marks, then save into the closet. Preview prefers the
//  signed upload URL when available, else the local prepared JPEG.
//

import SwiftUI

struct ScannerReviewView: View {
    @Bindable var viewModel: ScannerReviewViewModel
    var onFinished: () -> Void
    var onRetake: () -> Void

    var body: some View {
        ZStack {
            AstraColor.backgroundPrimary.ignoresSafeArea()
            content
        }
        .navigationTitle(String(localized: "Review Scan", comment: "Scanner review title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.start()
        }
        .onChange(of: viewModel.phase) { _, phase in
            if phase == .saved {
                onFinished()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading, .uploading, .analyzing, .saving:
            VStack(spacing: AstraSpacing.md) {
                ProgressView()
                    .tint(AstraColor.accentChampagne)
                Text(statusCopy)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
            }
            .accessibilityElement(children: .combine)

        case .missingDraft:
            failureBlock(
                message: String(localized: "That photo is no longer available. Capture it again.",
                                comment: "Scanner review missing draft"),
                retryTitle: String(localized: "Retake", comment: "Retake after missing draft"),
                retry: onRetake
            )

        case .uploadFailed(let error):
            failureBlock(
                message: error.errorDescription ?? String(localized: "Upload failed.", comment: "Upload failed fallback"),
                retryTitle: String(localized: "Retry Upload", comment: "Retry scanner upload"),
                retry: { Task { await viewModel.retryUpload() } }
            )

        case .analyzeFailed(let error):
            failureBlock(
                message: error.errorDescription ?? String(localized: "Analysis failed.", comment: "Analyze failed fallback"),
                retryTitle: String(localized: "Try Again", comment: "Retry scanner analyze"),
                retry: { Task { await viewModel.retryAnalyze() } }
            )

        case .saveFailed(let error):
            ScrollView {
                VStack(spacing: AstraSpacing.xl) {
                    failureBanner(error.errorDescription ?? String(localized: "Couldn't save.", comment: "Save failed fallback"))
                    reviewForm
                    saveControls
                }
                .padding(.vertical, AstraSpacing.lg)
            }

        case .ready, .saved:
            ScrollView {
                VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                    preview
                    reviewForm
                    if let ocr = viewModel.ocrText, !ocr.isEmpty {
                        ocrBlock(ocr)
                    }
                    saveControls
                }
                .padding(.vertical, AstraSpacing.lg)
            }
        }
    }

    private var statusCopy: String {
        switch viewModel.phase {
        case .uploading:
            String(localized: "Uploading the photo…", comment: "Scanner uploading status")
        case .analyzing:
            String(localized: "Kyra is reading the garment…", comment: "Scanner analyzing status")
        case .saving:
            String(localized: "Saving to your closet…", comment: "Scanner saving status")
        default:
            String(localized: "Loading…", comment: "Scanner review loading")
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        Group {
            if let url = viewModel.signedPreviewURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        localPreviewImage
                    default:
                        ProgressView().tint(AstraColor.accentChampagne)
                    }
                }
            } else {
                localPreviewImage
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
        .padding(.horizontal, AstraSpacing.pagePadding)
        .accessibilityLabel(Text("Scanned garment photo", comment: "Review preview accessibility"))
        .accessibilityIdentifier("scanner.review.preview")
    }

    @ViewBuilder
    private var localPreviewImage: some View {
        if let data = viewModel.localPreviewData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .fill(AstraColor.backgroundSecondary)
                .frame(height: 200)
        }
    }

    // MARK: - Form

    private var reviewForm: some View {
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
        optionalEnumChips(
            title: String(localized: "Pattern", comment: "Scan review pattern"),
            selection: $viewModel.pattern,
            options: GarmentPattern.allCases,
            titleFor: { $0.displayName },
            lowConfidence: viewModel.isLowConfidence(.pattern),
            footnote: viewModel.lowConfidenceFootnote(.pattern)
        )
    }

    private var fitPicker: some View {
        optionalEnumChips(
            title: String(localized: "Fit", comment: "Scan review fit"),
            selection: $viewModel.fit,
            options: ItemFit.allCases,
            titleFor: { $0.displayName },
            lowConfidence: viewModel.isLowConfidence(.fit),
            footnote: viewModel.lowConfidenceFootnote(.fit)
        )
    }

    private var conditionPicker: some View {
        optionalEnumChips(
            title: String(localized: "Condition", comment: "Scan review condition"),
            selection: $viewModel.condition,
            options: ItemCondition.allCases,
            titleFor: { $0.displayName },
            lowConfidence: viewModel.isLowConfidence(.condition),
            footnote: viewModel.lowConfidenceFootnote(.condition)
        )
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

    private func optionalEnumChips<Value: Hashable>(
        title: String,
        selection: Binding<Value?>,
        options: [Value],
        titleFor: @escaping (Value) -> String,
        lowConfidence: Bool,
        footnote: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(title)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
            if lowConfidence, let footnote, !footnote.isEmpty {
                Text(footnote)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.warningAmber)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AstraSpacing.sm) {
                    ForEach(options, id: \.self) { option in
                        AstraChip(titleFor(option), isSelected: selection.wrappedValue == option) {
                            selection.wrappedValue = selection.wrappedValue == option ? nil : option
                            AstraHaptics.selection()
                        }
                    }
                }
            }
        }
    }

    private func ocrBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(String(localized: "Label text", comment: "OCR block title"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
            Text(text)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
        .accessibilityIdentifier("scanner.review.ocr")
    }

    // MARK: - Actions

    private var saveControls: some View {
        VStack(spacing: AstraSpacing.md) {
            if let reason = viewModel.saveBlockedReason {
                Text(reason)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
            }
            Button(String(localized: "Save to Closet", comment: "Confirm scan review")) {
                Task { await viewModel.save() }
            }
            .buttonStyle(.astraPrimary)
            .disabled(!viewModel.canSave)
            .accessibilityIdentifier("scanner.review.save")

            Button(String(localized: "Retake", comment: "Retake from review")) {
                onRetake()
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("scanner.review.retake")
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
        .padding(.bottom, AstraSpacing.xl)
    }

    private func failureBlock(message: String, retryTitle: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: AstraSpacing.xl) {
            Spacer()
            failureBanner(message)
            Button(retryTitle, action: retry)
                .buttonStyle(.astraPrimary)
            Button(String(localized: "Retake", comment: "Retake after failure"), action: onRetake)
                .buttonStyle(.astraSecondary)
            Spacer()
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
    }

    private func failureBanner(_ message: String) -> some View {
        Text(message)
            .astraText(.body)
            .foregroundStyle(AstraColor.textPrimary)
            .multilineTextAlignment(.center)
            .padding(AstraSpacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .fill(AstraColor.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .strokeBorder(AstraColor.warningAmber, lineWidth: 1)
            )
            .accessibilityIdentifier("scanner.review.error")
    }
}
