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
                    ScannerReviewFormView(viewModel: viewModel)
                    saveControls
                }
                .padding(.vertical, AstraSpacing.lg)
            }

        case .ready, .saved:
            ScrollView {
                VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                    preview
                    ScannerReviewFormView(viewModel: viewModel)
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
