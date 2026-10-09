//
//  OutfitBuilderView.swift
//  AstraStyle
//
//  The Outfit builder screen (spec §6.13, P4-OUTFIT-12): flat-lay canvas,
//  category rail, tap-to-replace, long-press-to-lock, a live compatibility
//  meter, "Ask Kyra to finish", and Save. No network call happens in this
//  file — everything routes through `OutfitBuilderViewModel`.
//
//  WEAR FEEDBACK LIVES HERE TOO, GATED ON A REAL SAVED OUTFIT.
//  `WearFeedbackViewModel` (P4-OUTFIT-14) requires a real `outfits.id`
//  with real `outfit_items` rows — see that type's own header — so its
//  controls appear only once `viewModel.backingOutfitID` is non-nil: the
//  canvas was either opened on an existing outfit, or "Save as outfit"
//  has already run once in this session. Before that, showing the
//  controls would be exactly the dead-tap spec §22 rules out.
//

import SwiftUI

public struct OutfitBuilderView: View {
    @State private var viewModel: OutfitBuilderViewModel
    @State private var editingCategory: ClothingCategory?
    @State private var wearFeedbackViewModel: WearFeedbackViewModel?
    @State private var previewViewModel: InspirationViewModel?
    @Environment(AppRouter.self) private var router
    @Environment(AppContainer.self) private var container

    public init(viewModel: OutfitBuilderViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                content
            }
            .padding(.vertical, AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(String(localized: "Build an Outfit", comment: "Outfit builder screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .sheet(item: $editingCategory) { category in
            OutfitItemPickerSheet(
                category: category,
                items: viewModel.availableItems(for: category),
                currentItemID: viewModel.slots.first(where: { $0.category == category })?.item?.id,
                onSelect: { viewModel.selectItem($0, for: category) },
                onClear: { viewModel.clearItem(for: category) }
            )
        }
        .alert(
            Text(String(localized: "That didn't work", comment: "Title of the outfit builder generic action-error alert")),
            isPresented: actionErrorPresented,
            presenting: viewModel.actionError
        ) { _ in
            Button(String(localized: "OK", comment: "Dismisses an alert")) { viewModel.clearActionError() }
        } message: { error in
            Text(error.message)
        }
        .onChange(of: viewModel.backingOutfitID) { _, _ in
            wearFeedbackViewModel = viewModel.makeWearFeedbackViewModel()
        }
        .onAppear {
            wearFeedbackViewModel = viewModel.makeWearFeedbackViewModel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            skeleton

        case .failed(let error):
            OutfitBuilderErrorView(error: error) {
                Task { await viewModel.retry() }
            }
            .padding(.horizontal, AstraSpacing.pagePadding)

        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xl) {
            if viewModel.showsClosetRecommendations {
                recommendationsSection
            }

            nameField
                .padding(.horizontal, AstraSpacing.pagePadding)

            rail

            OutfitCompatibilityMeterView(breakdown: viewModel.currentCompatibility)
                .padding(.horizontal, AstraSpacing.pagePadding)

            if let reason = viewModel.kyraReason {
                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    Text(String(localized: "Kyra’s suggestion", comment: "Heading for the reason behind a completed outfit"))
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                    Text(reason)
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textSecondary)
                        .accessibilityIdentifier("outfitBuilder.kyraReason")
                }
                .padding(.horizontal, AstraSpacing.pagePadding)
            }

            actions
                .padding(.horizontal, AstraSpacing.pagePadding)

            if let wearFeedbackViewModel {
                Divider()
                    .padding(.horizontal, AstraSpacing.pagePadding)
                WearFeedbackControlsView(viewModel: wearFeedbackViewModel)
                    .padding(.horizontal, AstraSpacing.pagePadding)
            }
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text("Outfits from your closet")
                    .astraText(.title2)
                    .foregroundStyle(AstraColor.textPrimary)
                Text("Get three ideas using pieces you already own, then choose one to edit.")
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await viewModel.generateClosetRecommendations() }
            } label: {
                if viewModel.isLoadingRecommendations {
                    ProgressView().tint(AstraColor.accentChampagneAccessible)
                } else {
                    Text(viewModel.recommendations.isEmpty ? "Get three outfit ideas" : "Try three new ideas")
                }
            }
            .buttonStyle(.astraSecondary)
            .disabled(viewModel.isLoadingRecommendations)
            .accessibilityIdentifier("outfitBuilder.generateRecommendations")

            if let recommendationError = viewModel.recommendationError {
                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    Text(recommendationError)
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textSecondary)
                        .accessibilityIdentifier("outfitBuilder.recommendationError")
                    Button("Try again") {
                        Task { await viewModel.generateClosetRecommendations() }
                    }
                    .buttonStyle(.astraTertiary)
                    .accessibilityIdentifier("outfitBuilder.retryRecommendations")
                }
            }

            ForEach(viewModel.recommendations) { recommendation in
                recommendationCard(recommendation)
            }
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
    }

    private func recommendationCard(_ recommendation: OutfitRecommendation) -> some View {
        let ownedItems = recommendation.itemIDs.compactMap { id in viewModel.closetItems.first { $0.id == id } }
        let isSelected = viewModel.selectedRecommendationID == recommendation.id
        return AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(recommendation.name)
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                if !recommendation.reason.isEmpty {
                    Text(recommendation.reason)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(ownedItems.map(\.name).joined(separator: " · "))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("outfitBuilder.recommendationItems.\(recommendation.id.uuidString.lowercased())")
                Button(isSelected ? "Selected for editing" : "Choose this outfit") {
                    viewModel.selectRecommendation(recommendation)
                }
                .buttonStyle(.astraTertiary)
                .disabled(isSelected)
                .accessibilityIdentifier("outfitBuilder.chooseRecommendation.\(recommendation.id.uuidString.lowercased())")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("outfitBuilder.recommendation.\(recommendation.id.uuidString.lowercased())")
    }

    private var nameField: some View {
        AstraTextField(
            String(localized: "Name", comment: "Outfit builder name field label"),
            text: $viewModel.outfitName,
            placeholder: OutfitBuilderViewModel.defaultOutfitName,
            submitLabel: .done
        )
    }

    /// The category rail (spec §6.13: "Tops, Bottoms, Outerwear, Shoes,
    /// Watches, Accessories, Fragrance"). Order comes from
    /// `ClothingCategory.outfitBuilderRailOrder`, not `.allCases` — see
    /// that property's own header for why the two orders differ.
    private var rail: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AstraSpacing.sm) {
                ForEach(viewModel.slots) { slot in
                    OutfitBuilderSlotCard(
                        slot: slot,
                        onTap: { editingCategory = slot.category },
                        onToggleLock: { viewModel.toggleLock(for: slot.category) }
                    )
                }
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
    }

    private var actions: some View {
        VStack(spacing: AstraSpacing.sm) {
            Button("Preview these pieces") {
                let selectedOwnedIDs = Set(viewModel.filledItems.map(\.id))
                previewViewModel = InspirationViewModel(
                    closetOnly: true,
                    container: container,
                    initialItemIDs: selectedOwnedIDs
                )
            }
            .buttonStyle(.astraSecondary)
            .disabled(viewModel.filledItems.isEmpty)
            .accessibilityIdentifier("outfitBuilder.previewPieces")
            .sheet(item: $previewViewModel) { model in
                InspirationView(viewModel: model)
            }

            Button {
                Task { await viewModel.regenerate() }
            } label: {
                if viewModel.isRegenerating {
                    ProgressView().tint(AstraColor.accentChampagneAccessible)
                } else {
                    Text(String(localized: "Regenerate unlocked pieces", comment: "Re-ranks every unlocked outfit builder slot"))
                }
            }
            .buttonStyle(.astraSecondary)
            .disabled(viewModel.isRegenerating)
            .accessibilityIdentifier("outfitBuilder.regenerate")

            Button {
                Task { await viewModel.askKyraToFinish() }
            } label: {
                if viewModel.askKyraState == .working {
                    ProgressView().tint(AstraColor.accentChampagneAccessible)
                } else {
                    Text(String(localized: "Ask Kyra to finish", comment: "Outfit builder action: let Kyra fill the remaining slots"))
                }
            }
            .buttonStyle(.astraTertiary)
            .disabled(viewModel.askKyraState == .working)
            .accessibilityIdentifier("outfitBuilder.askKyra")

            AstraButton(
                title: viewModel.backingOutfitID == nil
                    ? String(localized: "Save as outfit", comment: "Creates a saved outfit from the builder canvas")
                    : String(localized: "Save changes", comment: "Updates the existing outfit without creating another outfit"),
                isLoading: viewModel.isSaving
            ) {
                Task { await viewModel.save() }
            }
            .disabled(viewModel.filledItems.isEmpty || viewModel.askKyraState == .working)
            .accessibilityIdentifier("outfitBuilder.save")

            if let savedOutfit = viewModel.savedOutfit {
                Button("Visualize this outfit") {
                    router.presentModal(.studioGeneration(outfitID: savedOutfit.id))
                }
                .buttonStyle(.astraSecondary)
                .accessibilityIdentifier("outfitBuilder.visualize")

                Button("Refine with Kyra") {
                    router.startAskKyra(
                        initialPrompt: "Help me refine this outfit. What could I change while keeping the pieces I own?",
                        outfitID: savedOutfit.id,
                        autoSend: true
                    )
                }
                .buttonStyle(.astraTertiary)
                .accessibilityIdentifier("outfitBuilder.refineWithKyra")
            }
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .fill(AstraColor.surfaceElevated)
                    .frame(height: AstraSpacing.xxxl)
            }
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized: "Loading your closet", comment: "Accessibility label for the outfit builder loading state")))
    }

    private var actionErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.actionError != nil },
            set: { isPresented in
                if !isPresented { viewModel.clearActionError() }
            }
        )
    }
}

extension ClothingCategory: Identifiable {
    public var id: String { rawValue }
}

// MARK: - Error state

private struct OutfitBuilderErrorView: View {
    let error: AstraError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: AstraSpacing.md) {
            Image(systemName: iconName)
                .astraIcon(.display)
                .foregroundStyle(AstraColor.textMuted)
                .accessibilityHidden(true)

            Text(String(localized: "We couldn't open the builder", comment: "Outfit builder error title"))
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(error.message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if error.isRetryable {
                Button(String(localized: "Try again", comment: "Retries loading the outfit builder"), action: onRetry)
                    .buttonStyle(.astraSecondary)
                    .padding(.top, AstraSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AstraSpacing.xxl)
        .accessibilityElement(children: .contain)
    }

    private var iconName: String {
        switch error.category {
        case .network: "wifi.slash"
        case .auth: "lock"
        case .rateLimited: "hourglass"
        default: "exclamationmark.triangle"
        }
    }
}

// MARK: - Previews

#Preview("Loaded") {
    NavigationStack {
        OutfitBuilderView(
            viewModel: OutfitBuilderViewModel(
                outfitRepository: MockOutfitRepository(),
                closetRepository: MockClosetRepository()
            )
        )
    }
    .environment(AppContainer.preview())
    .preferredColorScheme(.dark)
}
