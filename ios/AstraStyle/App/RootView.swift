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
            // Vertical-slice bypass (see Features/Slice/README.md): boots
            // straight into the temporary end-to-end scaffold screen
            // instead of the normal `AppRouteState` flow below, without
            // changing `AppRouteState`'s meaning or any of its branches for
            // the real app. Gated behind `AstraFeatureFlags
            // .verticalSliceEnabled` (Debug builds only, opt-in via the
            // `ASTRA_VERTICAL_SLICE` environment variable) so it can never
            // ship active in a Release build.
            if AstraFeatureFlags.verticalSliceEnabled {
                SliceRootView()
            } else {
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
            Color.clear.astraMarbleBackground(scrimmed: false)

            VStack(spacing: AstraSpacing.xl) {
                AstraMonogram(size: 84)
                AstraWordmark(showsTagline: true)
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
    /// The raw (unhashed) nonce for the in-flight sign-in attempt, set
    /// synchronously in the `SignInWithAppleButton` request closure and
    /// consumed in `handleSignInWithApple` — see `AppleSignInNonce`'s doc
    /// comment for why both the raw and hashed forms matter.
    @State private var currentNonce: String?
    @State private var isShowingEmailSheet = false

    var body: some View {
        ZStack {
            // Spec §3 names the welcome/paywall hero as one of the few surfaces
            // marble belongs on. Scrimmed so the buttons below stay legible.
            Color.clear.astraMarbleBackground()

            VStack(spacing: AstraSpacing.lg) {
                Spacer()

                VStack(spacing: AstraSpacing.lg) {
                    AstraMonogram(size: 72)
                    AstraWordmark()
                    Text("Meet Kyra, your personal stylist.")
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textSecondary)
                }

                Spacer()

                VStack(spacing: AstraSpacing.sm) {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                        // Nonce must be generated fresh per attempt and its
                        // SHA-256 hash attached here; the raw value is
                        // stashed for the Supabase exchange below. See
                        // `AppleSignInNonce`'s doc comment — sending the
                        // token without this makes Supabase's replay check
                        // meaningless, not just incomplete.
                        do {
                            let rawNonce = try AppleSignInNonce.random()
                            currentNonce = rawNonce
                            request.nonce = AppleSignInNonce.sha256(rawNonce)
                        } catch {
                            currentNonce = nil
                            authError = String(localized: "Couldn't start a secure sign-in. Please try again.")
                        }
                    } onCompletion: { result in
                        handleSignInWithApple(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: AstraSpacing.buttonRadius))
                    .disabled(isAuthenticating)
                    .accessibilityLabel(Text("Continue with Apple"))

                    AstraButton(title: String(localized: "Continue with Email", comment: "Auth entry action")) {
                        isShowingEmailSheet = true
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

                    legalFootnote
                }
                .padding(.horizontal, AstraSpacing.pagePadding)
                .padding(.bottom, AstraSpacing.lg)
            }
        }
        .sheet(isPresented: $isShowingEmailSheet) {
            EmailAuthSheet { _ in
                router.routeState = .onboarding
            }
        }
    }

    /// Spec §6.2 lists "Terms and Privacy links" as required on this screen,
    /// and App Store review expects them reachable before an account is
    /// created — not buried in Settings afterwards.
    private var legalFootnote: some View {
        VStack(spacing: AstraSpacing.xxs) {
            Text("By continuing you agree to our")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)

            HStack(spacing: AstraSpacing.xs) {
                Link(String(localized: "Terms of Service"), destination: AstraLegal.termsURL)
                Text("·")
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                Link(String(localized: "Privacy Policy"), destination: AstraLegal.privacyURL)
            }
            .astraText(.caption)
            .tint(AstraColor.accentChampagne)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, AstraSpacing.xs)
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
                    guard let nonce = currentNonce else {
                        authError = String(localized: "Your sign-in session expired. Please try again.")
                        return
                    }
                    _ = try await container.authRepository.signInWithApple(identityToken: identityToken, nonce: nonce)
                    router.routeState = .onboarding
                case .failure(let error):
                    authError = error.localizedDescription
                }
            } catch {
                authError = error.localizedDescription
            }
            currentNonce = nil
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
