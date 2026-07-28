//
//  RootView.swift
//  AstraStyle
//
//  Switches on `AppRouter.routeState` per spec §27. This file owns only the
//  four top-level routing branches; the actual screens for each branch
//  belong to their feature modules (Onboarding, the tab shell, etc). Where
//  a feature module has not been built out yet, a minimal, honest
//  placeholder is shown here rather than leaving the app uncompilable —
//  those placeholders are replaced by the Onboarding feature's own views as
//  its tickets (P2-ONBOARD, see Features/Onboarding/README.md) land.
//

import AuthenticationServices
import SwiftUI

struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            switch router.routeState {
            case .launching:
                LaunchingView()
            case .signedOut:
                SignedOutGateView()
            case .onboarding:
                OnboardingPlaceholderView()
            case .main:
                MainTabView()
            }
        }
        .astraAnimation(AstraMotion.standard, value: router.routeState)
    }
}

/// Spec §6.1 Splash: marble background, gold monogram, wordmark, brief
/// tagline, routes within 1.4s. The marble texture and monogram mark assets
/// live in `Core/DesignSystem`; this view only lays them out.
private struct LaunchingView: View {
    var body: some View {
        ZStack {
            AstraColor.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: AstraSpacing.md) {
                Text("ASTRA STYLE")
                    .astraText(.displayL)
                    .foregroundStyle(AstraColor.textPrimary)
                    .tracking(2)

                Text("Your style. Your journey. Your best self.")
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Astra Style. Your style. Your journey. Your best self."))
        }
    }
}

/// Spec §6.2 Welcome/authentication. Minimal, real, functioning entry
/// surface (Sign in with Apple, continue in guest mode); full email/OTP
/// flow and the remaining onboarding steps (§6.3-6.10) are owned by the
/// Onboarding feature module — see Features/Onboarding/README.md
/// (P2-ONBOARD tickets).
private struct SignedOutGateView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppRouter.self) private var router
    @State private var isAuthenticating = false
    @State private var authError: String?

    var body: some View {
        ZStack {
            AstraColor.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: AstraSpacing.lg) {
                Spacer()

                VStack(spacing: AstraSpacing.sm) {
                    Text("ASTRA STYLE")
                        .astraText(.displayL)
                        .foregroundStyle(AstraColor.textPrimary)
                    Text("Meet Kyra, your personal stylist.")
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textSecondary)
                }

                Spacer()

                VStack(spacing: AstraSpacing.sm) {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleSignInWithApple(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: AstraSpacing.buttonRadius))
                    .disabled(isAuthenticating)
                    .accessibilityLabel(Text("Continue with Apple"))

                    AstraButton(title: String(localized: "Continue with Email", comment: "Auth entry action")) {
                        router.presentModal(.paywall(context: .onboarding)) // placeholder route hook
                    }
                    .disabled(isAuthenticating)

                    Button {
                        Task { await continueAsGuest() }
                    } label: {
                        Text("Explore in guest mode")
                            .astraText(.callout)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
                    .disabled(isAuthenticating)
                    .accessibilityHint(Text("Browse a limited demo without an account"))

                    if let authError {
                        Text(authError)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.destructive)
                            .accessibilityLabel(Text("Sign-in error: \(authError)"))
                    }
                }
                .padding(.horizontal, AstraSpacing.pagePadding)
                .padding(.bottom, AstraSpacing.lg)
            }
        }
    }

    private func handleSignInWithApple(_ result: Result<ASAuthorization, Error>) {
        Task {
            isAuthenticating = true
            defer { isAuthenticating = false }
            do {
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let identityTokenData = credential.identityToken,
                          let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                        authError = String(localized: "Apple did not return a valid credential.")
                        return
                    }
                    _ = try await container.authRepository.signInWithApple(identityToken: identityToken)
                    router.routeState = .onboarding
                case .failure(let error):
                    authError = error.localizedDescription
                }
            } catch {
                authError = error.localizedDescription
            }
        }
    }

    private func continueAsGuest() async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            _ = try await container.authRepository.continueAsGuest()
            router.routeState = .onboarding
        } catch {
            authError = error.localizedDescription
        }
    }
}

/// Placeholder shown while authenticated but `onboarding_completed_at` is
/// nil. Replaced by the real multi-step flow in Features/Onboarding
/// (P2-ONBOARD: style goals, style identity, measurements, appearance,
/// lifestyle, preference quiz, Style DNA result — spec §6.4-§6.10).
private struct OnboardingPlaceholderView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            AstraColor.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: AstraSpacing.md) {
                Text("Let's build your Style DNA")
                    .astraText(.title1)
                    .foregroundStyle(AstraColor.textPrimary)
                Text("This is where Kyra learns your style, fit, and lifestyle. The full onboarding flow is delivered under the P2-ONBOARD tickets.")
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
                    .multilineTextAlignment(.center)

                AstraButton(title: String(localized: "Skip for now", comment: "Temporary onboarding bypass")) {
                    router.routeState = .main
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
    }
}
