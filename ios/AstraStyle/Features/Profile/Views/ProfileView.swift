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

public struct ProfileView: View {
    @Environment(AppRouter.self) private var router

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                title
                aboutCard
                whatsLiveCard
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
                        localized: "Live: Home (Today's Outfit, Wear This, paste a link, See this on you), Closet, Scan One Piece, Discover (your lookbooks), Ask Kyra.",
                        comment: "Profile what's live"
                    ))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(String(
                        localized: "Not live: Style Studio as a tab (Visualize is the door), shopping feeds, or a women's catalog. Women is a second graph, not a switch.",
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

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
