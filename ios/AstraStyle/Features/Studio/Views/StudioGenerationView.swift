//
//  StudioGenerationView.swift
//  AstraStyle
//
//  See today's look on him. Consent gates capture. The result always
//  wears the Visual Estimate badge. This is not a generation toy.
//

import PhotosUI
import SwiftUI

struct StudioGenerationView: View {
    @State private var viewModel: StudioGenerationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @Environment(AppContainer.self) private var container
    @State private var showsPaywall = false

    init(viewModel: StudioGenerationViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                    consentCopy
                    acknowledgment
                    if viewModel.hasGrantedConsent {
                        photoSection
                    }
                    statusSection
                }
                .padding(AstraSpacing.pagePadding)
            }
            .background(AstraColor.backgroundPrimary.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle(String(localized: "See this on you", comment: "Studio generation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close", comment: "Dismisses Studio")) { dismiss() }
                }
            }
            .task { await viewModel.onAppear() }
            .onChange(of: viewModel.pendingPaywall) { _, context in
                showsPaywall = context != nil
            }
            .sheet(
                isPresented: $showsPaywall,
                onDismiss: { viewModel.clearPendingPaywall() },
                content: {
                    PaywallView(
                        viewModel: PaywallViewModel(
                            context: .studioQuota,
                            purchasing: LiveStoreKitPurchasing(),
                            subscriptionRepository: container.subscriptionRepository
                        )
                    )
                }
            )
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let prepared = ReferenceImagePreparation.jpeg(from: data) else {
                        pickedItem = nil
                        return
                    }
                    viewModel.setPendingImage(prepared)
                    pickedItem = nil
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                ReferenceCameraPicker { data in
                    isShowingCamera = false
                    guard let prepared = ReferenceImagePreparation.jpeg(from: data) else { return }
                    viewModel.setPendingImage(prepared)
                } onCancel: {
                    isShowingCamera = false
                }
            }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
    }

    private var consentCopy: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(String(
                localized: "This uses a photo of you to picture the look. It is an estimate, not a fitting, and it is not sent to anyone except the image service that draws it.",
                comment: "Studio consent explanation"
            ))
            .astraText(.callout)
            .foregroundStyle(AstraColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Text(String(
                localized: "Terms \(StudioConsentTerms.currentVersion).",
                comment: "Studio consent terms version shown on screen"
            ))
            .astraText(.caption)
            .foregroundStyle(AstraColor.textMuted)
        }
    }

    private var acknowledgment: some View {
        Button {
            if viewModel.hasGrantedConsent {
                viewModel.withdrawConsent()
            } else {
                viewModel.grantConsent()
            }
            AstraHaptics.selection()
        } label: {
            HStack(alignment: .top, spacing: AstraSpacing.md) {
                Image(systemName: viewModel.hasGrantedConsent ? "checkmark.circle.fill" : "circle")
                    .astraIcon(.emphasis)
                    .foregroundStyle(
                        viewModel.hasGrantedConsent
                            ? AstraColor.accentChampagneAccessible
                            : AstraColor.textMuted
                    )
                    .accessibilityHidden(true)
                Text(String(
                    localized: "I've read this, and this photo is of me.",
                    comment: "Studio consent checkbox"
                ))
                .astraText(.body)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AstraSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .fill(AstraColor.backgroundSecondary)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("studio.consent")
    }

    @ViewBuilder
    private var photoSection: some View {
        if viewModel.existingReferencePath != nil, viewModel.pendingImageData == nil {
            Text(String(
                localized: "We'll use the photo already on your account.",
                comment: "Studio reuses onboarding reference"
            ))
            .astraText(.callout)
            .foregroundStyle(AstraColor.textSecondary)
        } else {
            captureControls
        }
    }

    @ViewBuilder
    private var captureControls: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            if let data = viewModel.pendingImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: AstraSize.referencePreviewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
                    .accessibilityLabel(Text("The photo you added", comment: "Studio reference preview"))
                Button(String(localized: "Remove this photo", comment: "Remove studio reference")) {
                    viewModel.removePendingImage()
                }
                .buttonStyle(.astraSecondary)
            } else {
                HStack(spacing: AstraSpacing.sm) {
                    PhotosPicker(selection: $pickedItem, matching: .images) {
                        Text(String(localized: "Choose photo", comment: "Studio photo library"))
                            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                    }
                    .buttonStyle(.astraSecondary)
                    Button(String(localized: "Take photo", comment: "Studio camera")) {
                        isShowingCamera = true
                    }
                    .buttonStyle(.astraSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch viewModel.phase {
        case .preparing:
            ProgressView()
                .tint(AstraColor.accentChampagne)
        case .ready:
            AstraButton(
                title: String(localized: "Generate", comment: "Starts Studio generation"),
                isLoading: false
            ) {
                Task { await viewModel.generate() }
            }
            .disabled(!viewModel.canGenerate)
            .accessibilityIdentifier("studio.generate")
        case .generating:
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                ProgressView()
                    .tint(AstraColor.accentChampagne)
                Text(String(localized: "Putting the look on you…", comment: "Studio generating"))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
            }
            .accessibilityIdentifier("studio.generating")
        case .complete:
            GeneratedImageContainer(
                accessibilityDescription: String(
                    localized: "Visual estimate of this outfit on you. Not a fitting.",
                    comment: "Studio result alt text"
                )
            ) {
                AstraRemoteImage(
                    url: viewModel.resultImageURL,
                    aspectRatio: 4.0 / 5.0,
                    accessibilityDescription: String(
                        localized: "Visual estimate of this outfit on you. Not a fitting.",
                        comment: "Studio result alt text"
                    )
                )
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(error.message)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                if error.isRetryable || viewModel.generation?.isRetryableWithoutCharge == true {
                    Button(String(localized: "Try Again", comment: "Retries Studio generation")) {
                        Task { await viewModel.retry() }
                    }
                    .buttonStyle(.astraSecondary)
                }
            }
        }
    }
}
