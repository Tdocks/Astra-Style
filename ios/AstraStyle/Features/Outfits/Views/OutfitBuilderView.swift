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
            Text(String(localized: "Ask Kyra to finish", comment: "Title of the Ask Kyra coming-soon alert")),
            isPresented: askKyraPresented
        ) {
            Button(String(localized: "OK", comment: "Dismisses an alert")) { viewModel.dismissAskKyraState() }
        } message: {
            Text(String(
                localized: "Kyra will be able to pick the rest of this look for you soon. For now, fill in each piece yourself.",
                comment: "Ask Kyra to finish coming-soon message"
            ))
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
            nameField
                .padding(.horizontal, AstraSpacing.pagePadding)

            rail

            OutfitCompatibilityMeterView(breakdown: viewModel.currentCompatibility)
                .padding(.horizontal, AstraSpacing.pagePadding)

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

            Button(String(localized: "Ask Kyra to finish", comment: "Outfit builder action: let Kyra fill the remaining slots")) {
                viewModel.askKyraToFinish()
            }
            .buttonStyle(.astraTertiary)
            .accessibilityIdentifier("outfitBuilder.askKyra")

            AstraButton(
                title: String(localized: "Save as outfit", comment: "Persists the current outfit builder canvas"),
                isLoading: viewModel.isSaving
            ) {
                Task { await viewModel.save() }
            }
            .disabled(viewModel.filledItems.isEmpty)
            .accessibilityIdentifier("outfitBuilder.save")
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

    private var askKyraPresented: Binding<Bool> {
        Binding(
            get: { viewModel.askKyraState == .comingSoon },
            set: { isPresented in
                if !isPresented { viewModel.dismissAskKyraState() }
            }
        )
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
    .preferredColorScheme(.dark)
}
