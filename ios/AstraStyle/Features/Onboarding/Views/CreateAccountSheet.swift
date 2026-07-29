//
//  CreateAccountSheet.swift
//  AstraStyle
//
//  Guest -> account upgrade (spec §7 "Guest migration to account";
//  ADR 0011). Presented via `AppModalRoute.createAccount(reason:)` from any
//  guest-mode surface — today the Profile tab's guest banner
//  (`GuestProfileView`); the intended landing spot once Phase 3's Closet
//  "add item" flow starts catching `GuestClosetError.capReached`.
//
//  Uses `AppleSignInProviding` + `AstraButton` (the pattern
//  `Features/Slice` already established) rather than the raw
//  `SignInWithAppleButton` chrome `RootView`'s Welcome screen uses — this is
//  a secondary sheet, not the primary first-run entry point, so staying on
//  design-system tokens end to end matters more here than matching Apple's
//  default button style exactly.
//

import SwiftUI

struct CreateAccountSheet: View {
    let reason: CreateAccountReason

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: CreateAccountViewModel?
    @State private var isShowingEmailSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                AstraColor.backgroundPrimary.ignoresSafeArea()
                content
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Not Now")) { dismiss() }
                        .foregroundStyle(AstraColor.textSecondary)
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = CreateAccountViewModel(
                    authRepository: container.authRepository,
                    guestMigrationService: container.guestMigrationService,
                    appleSignIn: AppleSignInCoordinator(),
                    guestUserID: container.sessionStore.currentSession?.userID
                )
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(AstraColor.backgroundPrimary)
        .sheet(isPresented: $isShowingEmailSheet) {
            EmailAuthSheet { session in
                Task {
                    await viewModel?.finishAfterExternalSignIn(session: session)
                    if viewModel?.isFinished == true { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: AstraSpacing.lg) {
            header

            if let migratedItemCount = viewModel?.migratedItemCount {
                Text("\(migratedItemCount) item(s) moved to your new account.")
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.successOlive)
            }

            switch viewModel?.phase {
            case .authenticating, .migratingCloset:
                ProgressView()
                    .tint(AstraColor.accentChampagne)
            default:
                actions
            }

            if case .failed(let message) = viewModel?.phase {
                Text(message)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AstraSpacing.pagePadding)
            }

            Spacer()
        }
        .padding(.top, AstraSpacing.xxl)
    }

    private var header: some View {
        VStack(spacing: AstraSpacing.sm) {
            AstraMonogram(size: 72)
            Text(title)
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
    }

    private var actions: some View {
        VStack(spacing: AstraSpacing.sm) {
            AstraButton(title: String(localized: "Continue with Apple")) {
                Task {
                    await viewModel?.continueWithApple()
                    if viewModel?.isFinished == true { dismiss() }
                }
            }

            Button(String(localized: "Continue with Email")) {
                isShowingEmailSheet = true
            }
            .buttonStyle(.astraSecondary)
        }
        .padding(.horizontal, AstraSpacing.pagePadding)
    }

    private var title: String {
        switch reason {
        case .closetCapReached:
            String(localized: "You've reached the 10-item guest limit")
        case .guestUpgrade:
            String(localized: "Create your account")
        }
    }

    private var message: String {
        switch reason {
        case .closetCapReached:
            String(localized: "Create an account to keep every piece you've added, sync your closet across devices, and add more.")
        case .guestUpgrade:
            String(localized: "Keep what you've built as a guest and unlock everything Astra Style offers.")
        }
    }
}
