//
//  GuestProfileView.swift
//  AstraStyle
//
//  The Profile tab's content while `SessionStore.isGuest` is true (spec
//  §6.2; ADR 0011) — shown instead of `MainTabView`'s generic
//  `FeaturePlaceholderView`. Deliberately real, not a placeholder: states
//  how many of the 10-item guest cap have been used and offers the actual
//  route to create an account, so "a guest who hits the cap" always has a
//  concrete next step available from Profile even before Phase 3's Closet
//  screens exist to trigger `GuestClosetError.capReached` directly.
//
//  All four required UI states are present: loading, loaded (which also
//  covers "empty" — zero items reads naturally as "0 of 10"), error, and
//  — via `AstraError.network`'s message text surfacing in the error state
//  — offline.
//

import SwiftUI

struct GuestProfileView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppRouter.self) private var router

    @State private var viewModel: GuestProfileViewModel?

    var body: some View {
        ZStack {
            AstraColor.backgroundPrimary.ignoresSafeArea()
            switch viewModel?.state {
            case nil, .loading:
                ProgressView()
                    .tint(AstraColor.accentChampagne)
            case .loaded(let itemCount):
                loadedView(itemCount: itemCount)
            case .error(let message):
                errorView(message: message)
            }
        }
        .navigationTitle(String(localized: "Profile"))
        .task {
            if viewModel == nil {
                viewModel = GuestProfileViewModel(closetRepository: container.closetRepository)
            }
            await viewModel?.load()
        }
    }

    private func loadedView(itemCount: Int) -> some View {
        VStack(spacing: AstraSpacing.lg) {
            AstraMonogram(size: 64)

            Text("You're exploring as a guest")
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)

            Text("\(itemCount) of \(GuestLimits.maxClosetItems) closet items used. Guest items stay on this device only — create an account to keep them, sync across devices, and add more.")
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AstraSpacing.pagePadding)

            AstraButton(title: String(localized: "Create an Account")) {
                router.presentModal(
                    .createAccount(reason: itemCount >= GuestLimits.maxClosetItems ? .closetCapReached : .guestUpgrade)
                )
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: AstraSpacing.md) {
            Image(systemName: "wifi.slash")
                .astraIcon(.display)
                .foregroundStyle(AstraColor.textMuted)
                .accessibilityHidden(true)
            Text(message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AstraSpacing.pagePadding)
            Button(String(localized: "Try Again")) {
                Task { await viewModel?.load() }
            }
            .buttonStyle(.astraSecondary)
        }
        .padding(AstraSpacing.pagePadding)
    }
}
