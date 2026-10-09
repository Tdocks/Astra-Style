//
//  ProfileView.swift
//  AstraStyle
//
//  The Profile tab's root (spec §4, §6.22). It composes the live closet
//  dashboard, private identity photo, score, Style DNA, subscription, and privacy controls.
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
                ProfileIdentityCard(
                    viewModel: ProfileIdentityViewModel(
                        profileRepository: container.profileRepository,
                        imageURLResolver: container.closetImageURLResolver
                    ),
                    canEdit: container.sessionStore.currentSession?.isAnonymous == false
                )
                ProfileDashboardCard(
                    viewModel: ProfileDashboardViewModel(
                        closetRepository: container.closetRepository,
                        outfitRepository: container.outfitRepository
                    )
                )
                WearStreakBanner(
                    viewModel: WearStreakViewModel(streakRepository: container.streakRepository),
                    showsBest: true
                )
                ProfileShoppingStatsCard(
                    viewModel: ProfileShoppingStatsViewModel(
                        shoppingRepository: container.shoppingRepository
                    )
                )
                ProfileWardrobeScoreCard(
                    viewModel: WardrobeScoreViewModel(closetRepository: container.closetRepository)
                )
                styleDNARow
                preferencesRow
                tasteRefinementRow
                profileNavigationRow(
                    title: String(localized: "Notifications", comment: "Profile notifications settings row"),
                    subtitle: String(localized: "Choose which style and closet reminders you receive.", comment: "Profile notifications subtitle"),
                    identifier: "profile.notificationsRow",
                    route: .notificationSettings
                )
                appearanceRow
                subscriptionRow
                aboutCard
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
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("profile.title")
    }

    private var styleDNARow: some View {
        profileNavigationRow(
            title: String(localized: "Style DNA", comment: "Profile Style DNA row"),
            subtitle: String(
                localized: "Your palette, silhouette, and the reasoning behind them.",
                comment: "Profile Style DNA subtitle"
            ),
            identifier: "profile.styleDNARow",
            route: .styleDNA
        )
    }

    private var preferencesRow: some View {
        profileNavigationRow(
            title: String(localized: "Preferences", comment: "Profile preferences row"),
            subtitle: String(
                localized: "Edit the answers behind your Style DNA.",
                comment: "Profile preferences subtitle"
            ),
            identifier: "profile.preferencesRow",
            route: .preferences
        )
    }

    private func profileNavigationRow(
        title: String,
        subtitle: String,
        identifier: String,
        route: ProfileRoute
    ) -> some View {
        Button {
            router.push(route)
        } label: {
            AstraCard {
                HStack(spacing: AstraSpacing.md) {
                    VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                        Text(title)
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.textPrimary)
                        Text(subtitle)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: AstraSpacing.sm)
                    Image(systemName: "chevron.right")
                        .astraIcon(.disclosure)
                        .foregroundStyle(AstraColor.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var tasteRefinementRow: some View {
        profileNavigationRow(
            title: "Refine your taste",
            subtitle: "Compare the full set of reference looks to sharpen all eight Style DNA dimensions.",
            identifier: "profile.tasteRefinementRow",
            route: .tasteRefinement
        )
    }

    private var appearanceRow: some View {
        Button {
            router.push(ProfileRoute.appearance)
        } label: {
            AstraCard {
                HStack(spacing: AstraSpacing.md) {
                    VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                        Text(String(localized: "Appearance & coloring", comment: "Profile appearance editor row"))
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.textPrimary)
                        Text(String(
                            localized: "Refine palette, contrast, collars, and visual estimates.",
                            comment: "Profile appearance editor subtitle"
                        ))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: AstraSpacing.sm)
                    Image(systemName: "chevron.right")
                        .astraIcon(.disclosure)
                        .foregroundStyle(AstraColor.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.appearanceRow")
    }

    private var subscriptionRow: some View {
        profileNavigationRow(
            title: String(localized: "Subscription", comment: "Profile subscription row"),
            subtitle: String(localized: "View your plan, restore purchases, or manage billing with Apple.", comment: "Profile subscription subtitle"),
            identifier: "profile.subscriptionRow",
            route: .subscriptionManagement
        )
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(String(localized: "About", comment: "Profile about section title"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .accessibilityAddTraits(.isHeader)
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
