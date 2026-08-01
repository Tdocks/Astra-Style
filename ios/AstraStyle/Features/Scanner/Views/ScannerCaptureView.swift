//
//  ScannerCaptureView.swift
//  AstraStyle
//
//  Single-item capture screen (spec §6.16 / P3-SCAN-01 + P3-SCAN-06).
//
//  Full-bleed camera preview when hardware is available; framing guide;
//  quality guidance banner fed by `CaptureQuality`; shutter; Photos import
//  as a first-class alternative. Stops at a local prepared draft — the
//  review screen (P3-SCAN-09) is not invented here.
//
//  Camera permission is requested only when this screen appears, via the
//  view model. Photos permission is requested only when Import is tapped
//  (PhotosPicker's own prompt) — never earlier (spec §7 / §22).
//

import PhotosUI
import SwiftUI

struct ScannerCaptureView: View {
    let viewModel: ScannerCaptureViewModel
    let captureSession: any CaptureSessionControlling

    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            AstraColor.backgroundPrimary.ignoresSafeArea()

            switch viewModel.phase {
            case .starting:
                ProgressView()
                    .tint(AstraColor.accentChampagne)
                    .accessibilityLabel(Text("Starting the camera", comment: "Scanner starting spinner"))

            case .capturing, .preparing:
                captureChrome

            case .draftReady(let prepared):
                draftConfirmation(prepared)

            case .failed(let error):
                failureState(error)
            }
        }
        .navigationTitle(String(localized: "Scan an Item", comment: "Scanner capture title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Close", comment: "Dismiss scanner")) {
                    dismiss()
                }
                .foregroundStyle(AstraColor.textSecondary)
                .accessibilityIdentifier("scanner.capture.close")
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task {
                // Same contract as OnboardingReferenceView: nil from
                // loadTransferable means the asset could not be vended —
                // treat as "nothing was chosen", not an error.
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    pickedItem = nil
                    return
                }
                await viewModel.importImageData(data)
                pickedItem = nil
            }
        }
    }

    // MARK: - Capture chrome

    private var captureChrome: some View {
        ZStack {
            if viewModel.showsShutter {
                CaptureSessionPreview(session: captureSession)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            framingGuide
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                if let guidance = viewModel.guidanceText {
                    guidanceBanner(guidance, severity: viewModel.guidanceSeverity)
                        .padding(.top, AstraSpacing.md)
                        .padding(.horizontal, AstraSpacing.pagePadding)
                        .transition(.opacity)
                }

                Spacer()

                if case .preparing = viewModel.phase {
                    ProgressView()
                        .tint(AstraColor.accentChampagne)
                        .padding(.bottom, AstraSpacing.md)
                        .accessibilityLabel(Text("Preparing the photo", comment: "Scanner preparing spinner"))
                }

                controls
                    .padding(.horizontal, AstraSpacing.pagePadding)
                    .padding(.bottom, AstraSpacing.xl)
            }
        }
        .animation(AstraMotion.standard, value: viewModel.guidanceText)
    }

    private var framingGuide: some View {
        RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
            .strokeBorder(AstraColor.accentChampagne.opacity(0.55), lineWidth: 2)
            .padding(AstraSpacing.xxxl)
            .accessibilityHidden(true)
    }

    private func guidanceBanner(_ text: String, severity: CaptureQualitySeverity) -> some View {
        Text(text)
            .astraText(.callout)
            .foregroundStyle(AstraColor.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AstraSpacing.md)
            .padding(.vertical, AstraSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.button, style: .continuous)
                    .fill(AstraColor.surfaceElevated.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.button, style: .continuous)
                    .strokeBorder(severityAccent(severity), lineWidth: 1)
            )
            .accessibilityIdentifier("scanner.capture.guidance")
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func severityAccent(_ severity: CaptureQualitySeverity) -> Color {
        switch severity {
        case .acceptable:
            AstraColor.successOlive
        case .warning:
            AstraColor.warningAmber
        case .blocking:
            AstraColor.warningAmber
        }
    }

    private var controls: some View {
        HStack(spacing: AstraSpacing.lg) {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Text(String(localized: "Import", comment: "Import a garment photo from the library"))
                    .frame(minWidth: AstraSpacing.xxxl * 2)
            }
            .buttonStyle(.astraSecondary)
            .disabled(viewModel.phase == .preparing)
            .accessibilityIdentifier("scanner.capture.import")

            if viewModel.showsShutter {
                Button {
                    Task { await viewModel.captureStill() }
                } label: {
                    Text(String(localized: "Capture", comment: "Take a garment photo"))
                        .frame(minWidth: AstraSpacing.xxxl * 2)
                }
                .buttonStyle(.astraPrimary)
                .disabled(viewModel.phase == .preparing || viewModel.isCapturingStill)
                .accessibilityIdentifier("scanner.capture.shutter")
            }
        }
    }

    // MARK: - Draft confirmation (honest gap before P3-SCAN-09)

    private func draftConfirmation(_ prepared: CapturePreparation.Prepared) -> some View {
        VStack(spacing: AstraSpacing.xl) {
            if let image = UIImage(data: prepared.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
                    .padding(.horizontal, AstraSpacing.pagePadding)
                    .accessibilityLabel(Text("Prepared garment photo", comment: "Scanner draft preview"))
                    .accessibilityIdentifier("scanner.capture.draft")
            }

            VStack(spacing: AstraSpacing.sm) {
                Text(String(localized: "Photo ready", comment: "Scanner draft title"))
                    .astraText(.title2)
                    .foregroundStyle(AstraColor.textPrimary)

                Text(String(localized: "Review and cataloguing come next — that screen is not built yet. Retake if you want a cleaner shot, or close and keep this for later.",
                             comment: "Honest gap copy: review screen not built"))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AstraSpacing.pagePadding)
            }

            VStack(spacing: AstraSpacing.md) {
                Button(String(localized: "Retake", comment: "Retake scanner photo")) {
                    Task { await viewModel.retake() }
                }
                .buttonStyle(.astraPrimary)
                .accessibilityIdentifier("scanner.capture.retake")

                Button(String(localized: "Close", comment: "Close scanner after draft")) {
                    dismiss()
                }
                .buttonStyle(.astraSecondary)
            }
            .padding(.horizontal, AstraSpacing.pagePadding)

            Spacer(minLength: 0)
        }
        .padding(.top, AstraSpacing.xl)
    }

    // MARK: - Failure

    private func failureState(_ error: AstraError) -> some View {
        VStack(spacing: AstraSpacing.xl) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .astraIcon(.display)
                .foregroundStyle(AstraColor.warningAmber)
                .accessibilityHidden(true)

            Text(error.errorDescription ?? String(localized: "Something went wrong", comment: "Generic scanner error title"))
                .astraText(.body)
                .foregroundStyle(AstraColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AstraSpacing.pagePadding)
                .accessibilityIdentifier("scanner.capture.error")

            Button(String(localized: "Try Again", comment: "Retry scanner after failure")) {
                Task { await viewModel.clearFailureAndReturnToCapture() }
            }
            .buttonStyle(.astraPrimary)
            .accessibilityIdentifier("scanner.capture.retry")

            PhotosPicker(selection: $pickedItem, matching: .images) {
                Text(String(localized: "Import a Photo Instead", comment: "Fallback import after camera failure"))
            }
            .buttonStyle(.astraSecondary)

            Spacer()
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
    }
}
