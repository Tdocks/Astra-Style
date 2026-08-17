//
//  ProfileView.swift
//  AstraStyle
//
//  The Profile tab's root (spec §4, §6.22). Deliberately thin: the full
//  profile-and-stats screen — Style DNA summary, Wardrobe Score, items
//  owned, cost per wear, Style Journey — is `P7-HOME-05`'s scope, not
//  this pass's. What this pass owns is `P7-PRIVACY-02`/`P7-PRIVACY-03`:
//  somewhere honest to reach account deletion from. Building a stats
//  dashboard here to look less bare would be building the wrong ticket's
//  screen under this one's number, and something P7-HOME-05 would then
//  have to either keep in step with or tear out.
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
