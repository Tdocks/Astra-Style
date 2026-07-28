//
//  SliceView.swift
//  AstraStyle
//
//  The vertical slice's single screen: sign in with Apple, a manual
//  add-garment form, a "Generate Outfit" button that calls the real
//  `POST /outfits/generate` Edge Function, the resulting outfit, and a
//  "Mark Worn" action. See `README.md` in this directory for scope and
//  why this module exists outside the normal five-tab IA.
//
//  Every value below comes from `Core/DesignSystem` tokens — no hardcoded
//  colors, fonts, spacing, or radii (CLAUDE.md's design-token rule).
//

import SwiftUI

/// Entry point wired into `RootView` behind `AstraFeatureFlags
/// .verticalSliceEnabled`. Reads `AppContainer` from the environment (the
/// one place allowed to construct concrete dependencies) and builds the
/// view model from repository protocols only.
struct SliceRootView: View {
    @Environment(AppContainer.self) private var container
    @State private var viewModel: SliceViewModel?

    var body: some View {
        Group {
            if let viewModel {
                SliceView(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AstraColor.accentChampagne)
            }
        }
        .onAppear {
            guard viewModel == nil else { return }
            viewModel = SliceViewModel(
                authRepository: container.authRepository,
                closetRepository: container.closetRepository,
                outfitRepository: container.outfitRepository,
                appleSignIn: AppleSignInCoordinator()
            )
        }
    }
}

public struct SliceView: View {
    @State private var viewModel: SliceViewModel

    public init(viewModel: SliceViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                    if viewModel.isOffline {
                        offlineBanner
                    }

                    switch viewModel.authPhase {
                    case .signedOut, .signingIn:
                        signInSection
                    case .signedIn:
                        garmentsSection
                        addGarmentSection
                        outfitSection
                    }
                }
                .padding(.horizontal, AstraSpacing.pagePadding)
                .padding(.vertical, AstraSpacing.pagePadding)
            }
            .background(AstraColor.backgroundPrimary.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle("Vertical Slice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign Out") {
                            Task { await viewModel.signOut() }
                        }
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                    }
                }
            }
            .task {
                await viewModel.restoreSessionIfNeeded()
            }
        }
    }

    // MARK: - Offline

    private var offlineBanner: some View {
        HStack(spacing: AstraSpacing.xs) {
            Image(systemName: "wifi.slash")
                .astraIcon(.inline)
            Text("You're offline. Some actions won't work until you're back online.")
                .astraText(.caption)
        }
        .foregroundStyle(AstraColor.warningAmber)
        .padding(AstraSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                .fill(AstraColor.backgroundSecondary)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sign in

    private var signInSection: some View {
        VStack(spacing: AstraSpacing.lg) {
            VStack(spacing: AstraSpacing.xs) {
                Text("Astra Style")
                    .astraText(.displayL)
                    .foregroundStyle(AstraColor.textPrimary)
                Text("Vertical slice: sign in, add a garment, generate an outfit, mark it worn.")
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            AstraButton(
                title: String(localized: "Sign in with Apple"),
                isLoading: viewModel.authPhase == .signingIn
            ) {
                Task { await viewModel.signInWithApple() }
            }
            .accessibilityLabel(Text("Sign in with Apple"))
            .accessibilityHint(Text("Starts the real Apple sign-in flow and creates a Supabase session."))

            if case .failed(let error) = viewModel.garmentsState {
                errorText(error)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AstraSpacing.xxxl)
    }

    // MARK: - Garments

    @ViewBuilder
    private var garmentsSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: "Your Closet", eyebrow: "STEP 2")

            switch viewModel.garmentsState {
            case .loading:
                ProgressView()
                    .tint(AstraColor.accentChampagne)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AstraSpacing.lg)

            case .empty:
                Text("No garments yet. Add your first one below.")
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)

            case .loaded(let items):
                VStack(spacing: AstraSpacing.xs) {
                    ForEach(items) { item in
                        garmentRow(item)
                    }
                }

            case .failed(let error):
                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    errorText(error, isOffline: viewModel.isOffline)
                    Button("Retry") {
                        Task { await viewModel.loadGarments() }
                    }
                    .buttonStyle(.astraTertiary)
                    .accessibilityLabel(Text("Retry loading your closet"))
                }
            }
        }
    }

    private func garmentRow(_ item: ClosetItem) -> some View {
        HStack(spacing: AstraSpacing.sm) {
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(item.name)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textPrimary)
                Text(garmentSubtitle(for: item))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
            }
            Spacer()
            if item.wearCount > 0 {
                Text("Worn \(item.wearCount)×")
                    .astraText(.micro)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
            }
        }
        .padding(AstraSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                .fill(AstraColor.backgroundSecondary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(item.name), \(item.category.displayName)\(item.primaryColor.map { ", \($0)" } ?? "")"))
    }

    // MARK: - Add garment

    private var addGarmentSection: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                AstraSectionHeader(title: "Add a Garment")

                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text("Name")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                    TextField("e.g. Navy Merino Sweater", text: $viewModel.draftName)
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textPrimary)
                        .padding(AstraSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                                .fill(AstraColor.backgroundSecondary)
                        )
                        .accessibilityLabel(Text("Garment name"))
                }

                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text("Category")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: AstraSpacing.xs) {
                            ForEach(ClothingCategory.allCases, id: \.self) { category in
                                AstraChip(
                                    category.displayName,
                                    isSelected: viewModel.draftCategory == category
                                ) {
                                    viewModel.draftCategory = category
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text("Primary Color")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                    TextField("e.g. navy", text: $viewModel.draftPrimaryColor)
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textPrimary)
                        .padding(AstraSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                                .fill(AstraColor.backgroundSecondary)
                        )
                        .accessibilityLabel(Text("Garment primary color"))
                }

                if case .failed(let error) = viewModel.addGarmentState {
                    errorText(error)
                }

                AstraButton(
                    title: String(localized: "Save Garment"),
                    isLoading: viewModel.addGarmentState == .saving
                ) {
                    Task { await viewModel.addGarment() }
                }
                .accessibilityLabel(Text("Save garment"))
            }
        }
    }

    // MARK: - Outfit generation

    @ViewBuilder
    private var outfitSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: "Today's Outfit", eyebrow: "STEP 3")

            AstraButton(
                title: String(localized: "Generate Outfit"),
                isLoading: viewModel.outfitState == .generating
            ) {
                Task { await viewModel.generateOutfit() }
            }
            .disabled(!viewModel.canGenerateOutfit)
            .accessibilityLabel(Text("Generate outfit"))
            .accessibilityHint(
                Text(
                    viewModel.canGenerateOutfit
                        ? "Calls the outfit generation service using your closet."
                        : "Add at least one garment first."
                )
            )

            switch viewModel.outfitState {
            case .idle, .generating:
                EmptyView()

            case .loaded(let outfit):
                outfitCard(outfit)

            case .failed(let error):
                errorText(error, isOffline: viewModel.isOffline)
            }
        }
    }

    private func outfitCard(_ outfit: SliceOutfitDisplay) -> some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(outfit.name)
                        .astraText(.title2)
                        .foregroundStyle(AstraColor.textPrimary)
                    Text(outfit.reason)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                    Text("Compatibility: \(outfit.compatibilityScore)")
                        .astraText(.micro)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                }

                if outfit.items.isEmpty {
                    Text("Kyra picked items that aren't in your local list yet — pull to refresh your closet.")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                } else {
                    VStack(spacing: AstraSpacing.xs) {
                        ForEach(outfit.items) { item in
                            garmentRow(item)
                        }
                    }
                }

                if outfit.missingItemCount > 0 {
                    Text("\(outfit.missingItemCount) additional slot(s) need an item you don't own yet.")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                }

                markWornControl
            }
        }
    }

    @ViewBuilder
    private var markWornControl: some View {
        switch viewModel.markWornState {
        case .idle, .saving:
            AstraButton(
                title: String(localized: "Mark Worn"),
                isLoading: viewModel.markWornState == .saving
            ) {
                Task { await viewModel.markWorn() }
            }
            .accessibilityLabel(Text("Mark this outfit worn today"))

        case .saved:
            HStack(spacing: AstraSpacing.xxs) {
                Image(systemName: "checkmark.circle.fill")
                    .astraIcon(.inline)
                Text("Marked worn today")
                    .astraText(.callout)
            }
            .foregroundStyle(AstraColor.successOlive)
            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            .accessibilityElement(children: .combine)

        case .failed(let error):
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                errorText(error, isOffline: viewModel.isOffline)
                AstraButton(title: String(localized: "Try Again")) {
                    Task { await viewModel.markWorn() }
                }
                .accessibilityLabel(Text("Retry marking this outfit worn"))
            }
        }
    }

    private func garmentSubtitle(for item: ClosetItem) -> String {
        var parts = [item.category.displayName]
        if let color = item.primaryColor, !color.isEmpty {
            parts.append(color)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Shared error presentation

    private func errorText(_ error: AstraError, isOffline: Bool = false) -> some View {
        HStack(alignment: .top, spacing: AstraSpacing.xs) {
            Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle")
                .astraIcon(.inline)
            Text(error.message)
                .astraText(.caption)
        }
        .foregroundStyle(AstraColor.destructive)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Error: \(error.message)"))
    }
}
