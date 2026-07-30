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
                    OnboardingFlowView(
                        model: OnboardingViewModel(
                            // Scoped per user so one person's draft is never
                            // handed to another account on a shared device.
                            store: FileOnboardingDraftStore(
                                userScope: container.sessionStore.currentSession?.userID.uuidString
                                    ?? "anonymous"
                            ),
                            profileRepository: container.profileRepository,
                            sessionStore: container.sessionStore
                        )
                    )
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
                AstraMonogram(size: 100)
                AstraWordmark(showsTagline: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Astra Style. Your style. Your journey. Your best self."))
        }
        .astraOnMarble()
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
    /// Shown in place of a legal document that has not been published yet.
    @State private var legalNotice: String?

    var body: some View {
        ZStack {
            // Spec §3 names the welcome/paywall hero as one of the few surfaces
            // marble belongs on. Scrimmed so the buttons below stay legible.
            Color.clear.astraMarbleBackground()

            // Spec §19 requires full Dynamic Type support. At the largest
            // accessibility sizes this screen's content is taller than the
            // fixed layout below can show without truncating text — a plain
            // `VStack` in a `ZStack` clips/squeezes instead of growing. The
            // `GeometryReader` + `ScrollView` pairing keeps the original
            // spacer-driven layout (content fills the screen, top and bottom
            // groups pushed apart) at ordinary text sizes via `minHeight`,
            // while letting the screen scroll instead of truncating once
            // content genuinely doesn't fit.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: AstraSpacing.lg) {
                        Spacer(minLength: AstraSpacing.xl)

                        VStack(spacing: AstraSpacing.lg) {
                            AstraMonogram(size: 88)
                            AstraWordmark()
                            Text("Meet Kyra, your personal stylist.")
                                .astraText(.body)
                                .foregroundStyle(AstraColor.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, AstraSpacing.pagePadding)

                        Spacer(minLength: AstraSpacing.xl)

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
                                    .multilineTextAlignment(.center)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .disabled(isAuthenticating)
                            .accessibilityHint(Text("Browse a limited demo without an account"))

                            if let authError {
                                Text(authError)
                                    .astraText(.caption)
                                    .foregroundStyle(AstraColor.destructive)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(nil)
                                    .accessibilityLabel(Text("Sign-in error: \(authError)"))
                            }

                            legalFootnote
                        }
                        .padding(.horizontal, AstraSpacing.pagePadding)
                        .padding(.bottom, AstraSpacing.lg)
                    }
                    .frame(minHeight: proxy.size.height)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .astraOnMarble()
        .sheet(isPresented: $isShowingEmailSheet) {
            EmailAuthSheet { _ in
                router.routeState = AppRouter.postAuthenticationRoute
            }
        }
    }

    /// Spec §6.2 lists "Terms and Privacy links" as required on this screen,
    /// and App Store review expects them reachable before an account is
    /// created — not buried in Settings afterwards.
    ///
    /// `ViewThatFits` reflows the row: a single horizontal line ("Terms of
    /// Service · Privacy Policy") whenever that fits, and a vertical stack
    /// of the two links once the Dynamic Type size makes the horizontal row
    /// wider than the screen — spec §19's full Dynamic Type support applied
    /// to a row that previously just truncated ("Terms of S… · Privacy…")
    /// instead of reflowing.
    private var legalFootnote: some View {
        VStack(spacing: AstraSpacing.xxs) {
            Text("By continuing you agree to our")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .multilineTextAlignment(.center)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AstraSpacing.xs) {
                    termsLink
                    Text("·")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                    privacyLink
                }

                VStack(spacing: AstraSpacing.xxs) {
                    termsLink
                    privacyLink
                }
            }
            .astraText(.caption)
            // `accentChampagneAccessible`, not `accentChampagne`. These are
            // text links, and the plain token is #B8914E in light mode —
            // 2.68:1 against the light background, which fails WCAG AA and is
            // barely legible in practice (confirmed on the simulator once
            // light mode became reachable). The accessible variant is #8A6A2E
            // at 4.62:1. Both resolve to the same value in dark mode.
            .tint(AstraColor.accentChampagneAccessible)

            if let legalNotice {
                Text(legalNotice)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("welcome.legalNotice")
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, AstraSpacing.xs)
    }

    /// Stable identifier so UI tests can target this link unambiguously —
    /// `Link` surfaces as a `.button` in the accessibility tree, not a
    /// `.link`, so `app.links["Terms of Service"]` never matched it (see
    /// `Tests/UITests/ScreenQAUITests.swift`). The unpublished branch below is
    /// a `Button` for the same reason: same accessibility role, so the control
    /// keeps its identity whichever state it is in.
    private var termsLink: some View {
        legalLink(
            title: String(localized: "Terms of Service"),
            url: AstraLegal.termsURL,
            identifier: "welcome.termsLink",
            unavailableNotice: String(
                localized: "Our Terms of Service will be published before Astra Style is released."
            )
        )
    }

    private var privacyLink: some View {
        legalLink(
            title: String(localized: "Privacy Policy"),
            url: AstraLegal.privacyURL,
            identifier: "welcome.privacyLink",
            unavailableNotice: String(
                localized: "Our Privacy Policy will be published before Astra Style is released."
            )
        )
    }

    /// A legal document link that tells the truth about a document that does
    /// not exist yet.
    ///
    /// `AstraLegal.termsURL` and `privacyURL` are `nil` until the domain is
    /// registered and the documents are published (see AstraLegal.swift). The
    /// old shape linked to `astrastyle.app`, which is NXDOMAIN, so tapping
    /// either one opened Safari on a DNS error — a dead control that looked
    /// alive, and an App Store review blocker. This keeps the control present
    /// and doing something visible (§22: "no dead buttons") while being honest
    /// that there is nothing to read yet. It becomes a real `Link` the moment
    /// `AstraLegal.isPublished` flips, with no other change anywhere.
    @ViewBuilder
    private func legalLink(
        title: String,
        url: URL?,
        identifier: String,
        unavailableNotice: String
    ) -> some View {
        if let url {
            Link(title, destination: url)
                .accessibilityIdentifier(identifier)
        } else {
            Button(title) { legalNotice = unavailableNotice }
                .accessibilityIdentifier(identifier)
                .accessibilityHint(Text("Not published yet"))
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
                    guard let nonce = currentNonce else {
                        authError = String(localized: "Your sign-in session expired. Please try again.")
                        return
                    }
                    _ = try await container.authRepository.signInWithApple(identityToken: identityToken, nonce: nonce)
                    router.routeState = AppRouter.postAuthenticationRoute
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
            router.routeState = AppRouter.postAuthenticationRoute
        } catch {
            authError = error.localizedDescription
        }
    }
}
