//
//  ProfileView.swift
//  AstraStyle
//
//  The Profile tab's root (spec §4, §6.22). Deliberately thin: the full
//  profile-and-stats screen — Style DNA summary, Wardrobe Score, items
//  owned, cost per wear, Style Journey — is `P7-HOME-05`'s scope, not
//  this pass's. ADR 0015 added About (marketing version + build) and an
//  honest live/next inventory so dogfood can tell binaries apart without
//  growing that dashboard. Privacy & Data remains the App Store gate
//  (`P7-PRIVACY-02`/`P7-PRIVACY-03`).
//
//  NO IDENTITY HEADER, ON PURPOSE. `Profile.displayName`/`avatarURL` are
//  real, fetchable fields, and a "Hi, [name]" line would be an easy
//  addition — but it is the first sentence of the screen P7-HOME-05 owns
//  ("profile image, Style DNA...", `Features/Profile/README.md`), and
//  adding half of that header today means deciding, once P7-HOME-05
//  lands, which of two files owns the `fetchCurrentProfile()` call site.
//  Leaving it out entirely is the version of "minimal" that does not have
//  to be partially undone later.
//

import SwiftUI
import AuthenticationServices

public struct ProfileView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppContainer.self) private var container

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                title
                WearStreakBanner(
                    viewModel: WearStreakViewModel(streakRepository: container.streakRepository),
                    showsBest: true
                )
                ProfileShoppingStatsCard(
                    viewModel: ProfileShoppingStatsViewModel(
                        shoppingRepository: container.shoppingRepository
                    )
                )
                aboutCard
                whatsLiveCard
                ProfileReferralCard(viewModel: ProfileReferralViewModel(
                    profileRepository: container.profileRepository
                ))
                if container.sessionStore.currentSession?.isAnonymous == true {
                    ProfileGuestAccountCard()
                }
                privacyAndDataRow
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
            .padding(.vertical, AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: some View {
        Text(String(localized: "Profile", comment: "Profile tab title"))
            .astraText(.displayL)
            .foregroundStyle(AstraColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(String(localized: "About", comment: "Profile about section title"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
            AstraCard {
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text("Astra Style")
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                    Text(AstraAppVersion.current.displayLabel)
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textSecondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("profile.about.version")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Astra Style \(AstraAppVersion.current.displayLabel)"))
    }

    /// Honest inventory of this binary. Studio and Discover are specified
    /// and unfinished; naming them here as next — not as tabs — is the
    /// §22 version of that fact (ADR 0015).
    private var whatsLiveCard: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(String(localized: "This build", comment: "Profile what's-live section title"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
            AstraCard {
                VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                    Text(String(
                        localized: "Live: Home (Today's Outfit, Wear This, paste a link, See this on you, streak), Closet, Scan One Piece, Discover (your lookbooks and worn looks), Shop (curated catalog), Ask Kyra.",
                        comment: "Profile what's live"
                    ))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(String(
                        localized: "Not live: Style Studio as a tab (Visualize is the door).",
                        comment: "Profile what's next"
                    ))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("profile.whatsLive")
    }

    private var privacyAndDataRow: some View {
        Button {
            router.push(ProfileRoute.privacyAndData)
        } label: {
            AstraCard {
                HStack(spacing: AstraSpacing.md) {
                    VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                        Text(String(localized: "Privacy & Data", comment: "Profile row opening privacy and data controls"))
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.textPrimary)
                        Text(String(
                            localized: "Delete your account and everything in it.",
                            comment: "Subtitle under the privacy & data row"
                        ))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                    }
                    Spacer(minLength: AstraSpacing.sm)
                    Image(systemName: "chevron.right")
                        .astraIcon(.disclosure)
                        .foregroundStyle(AstraColor.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.privacyAndDataRow")
        .accessibilityHint(Text(String(
            localized: "Opens privacy and data controls",
            comment: "VoiceOver hint for the privacy & data row"
        )))
    }
}

private struct ProfileReferralCard: View {
    @State private var viewModel: ProfileReferralViewModel

    init(viewModel: ProfileReferralViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(String(localized: "Send this to a guy who hates shopping", comment: "Profile referral prompt"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
            AstraCard {
                VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                    if let code = viewModel.code {
                        Text(code)
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.textPrimary)
                            .monospaced()
                            .accessibilityIdentifier("profile.referral.code")
                    }
                    ShareLink(item: viewModel.shareText) {
                        Label(
                            String(localized: "Share your code", comment: "Shares the referral code"),
                            systemImage: "square.and.arrow.up"
                        )
                        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                    }
                    .buttonStyle(.astraSecondary)
                    .accessibilityIdentifier("profile.referral.share")

                    if !viewModel.referredAlready {
                        TextField(
                            String(localized: "Have a code?", comment: "Apply someone else's referral"),
                            text: $viewModel.incomingCode
                        )
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textPrimary)
                        .accessibilityIdentifier("profile.referral.incoming")
                        Button {
                            Task { await viewModel.applyIncomingCode() }
                        } label: {
                            Text(String(localized: "Apply code", comment: "Applies a referral code"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.astraSecondary)
                        .disabled(viewModel.isApplying)
                    }
                    if let note = viewModel.note {
                        Text(note)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await viewModel.onAppear() }
    }
}

struct ProfileGuestAccountCard: View {
    @Environment(AppContainer.self) private var container
    @State private var currentNonce: String?
    @State private var isShowingEmailSheet = false
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(String(localized: "Keep this closet", comment: "Anonymous account link title"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
            AstraCard {
                VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                    Text(String(
                        localized: "You're on a trial without an account. Link Apple or email to keep this closet and your answers — same user, no migration hop.",
                        comment: "Anonymous account link explanation"
                    ))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                        do {
                            let rawNonce = try AppleSignInNonce.random()
                            currentNonce = rawNonce
                            request.nonce = AppleSignInNonce.sha256(rawNonce)
                        } catch {
                            currentNonce = nil
                            errorMessage = String(localized: "Couldn't start a secure sign-in. Please try again.")
                        }
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: AstraSpacing.buttonRadius))
                    .disabled(isWorking)
                    AstraButton(title: String(localized: "Link email", comment: "Anonymous account email link")) {
                        isShowingEmailSheet = true
                    }
                    .disabled(isWorking)
                    if let errorMessage {
                        Text(errorMessage)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("profile.guestAccount")
        .sheet(isPresented: $isShowingEmailSheet) {
            EmailAuthSheet(onAuthenticated: { _ in }, linksAnonymousAccount: true)
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            errorMessage = String(localized: "Sign in with Apple didn't finish. Please try again.")
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                errorMessage = String(localized: "Sign in with Apple didn't finish. Please try again.")
                return
            }
            currentNonce = nil
            isWorking = true
            Task {
                defer { isWorking = false }
                do {
                    _ = try await container.authRepository.linkAppleIdentity(
                        identityToken: identityToken,
                        nonce: nonce
                    )
                    try await container.closetRepository.migrateGuestLocalImages()
                } catch let error as AstraError {
                    errorMessage = error.message
                } catch {
                    errorMessage = String(localized: "Couldn't link Apple to this trial. Please try again.")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environment(AppRouter())
    .environment(AppContainer.preview())
    .preferredColorScheme(.dark)
}
