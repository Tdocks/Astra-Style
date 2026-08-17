//
//  PrivacyAndDataView.swift
//  AstraStyle
//
//  `ProfileRoute.privacyAndData` (spec §29 "Privacy and data controls").
//  One row, not several — see below for why.
//
//  WHY THERE IS NO "EXPORT MY DATA" ROW. `ProfileRepository
//  .exportPersonalData()` is real Swift and a real protocol requirement
//  (spec §29, ticket P7-PRIVACY-03), but `LiveProfileRepository
//  .exportPersonalData()`'s own header says what it actually does: sign a
//  URL for `exports/users/{uid}/export-latest.json`, an object NOTHING in
//  this codebase ever writes. There is no Edge Function, scheduled job,
//  or migration that produces it — `supabase/functions/` has no export
//  endpoint and no `exports` bucket is created anywhere. Every real tap
//  would sign a URL for an object that has never existed and 404. Spec
//  §22 rules out exactly this: a control whose tap cannot succeed. So the
//  row is absent rather than present-and-broken, matching this codebase's
//  own rule for an unbuilt path (`ClosetDestinationView`'s `.editItem`
//  case) — except this one has no honest placeholder to show either,
//  because "not built yet" is a screen and this would need to be a
//  WORKING download. P7-PRIVACY-03 is not satisfied by this file; see the
//  note in `Features/Profile/README.md`.
//
//  WHY THERE IS NO "DELETE INDIVIDUAL PHOTOS" OR "STYLE MEMORIES" ROW
//  EITHER, despite the old README listing both here. Those are
//  `P7-PRIVACY-04` and part of `P5-KYRA-17` — different tickets, with
//  their own repository methods (`ClosetRepository`'s per-image delete,
//  `KyraRepository.deleteMemory(id:)`) this pass does not touch. A row
//  for either here would be reaching into another ticket's scope to fill
//  space. They belong on this same screen once built.
//

import SwiftUI

struct PrivacyAndDataView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                AstraSectionHeader(
                    title: String(localized: "Privacy & Data", comment: "Privacy and data controls screen title")
                )

                deleteAccountRow
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
            .padding(.vertical, AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationTitle(String(localized: "Privacy & Data", comment: "Privacy and data controls navigation bar title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var deleteAccountRow: some View {
        Button {
            router.push(ProfileRoute.accountDeletion)
        } label: {
            AstraCard {
                HStack(spacing: AstraSpacing.md) {
                    VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                        Text(String(localized: "Delete My Account", comment: "Row opening the account deletion flow"))
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.destructive)
                        Text(String(
                            localized: "Permanently remove your account and everything in it.",
                            comment: "Subtitle under the delete-account row"
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
        .accessibilityIdentifier("privacyAndData.deleteAccountRow")
        .accessibilityHint(Text(String(
            localized: "Opens the account deletion flow",
            comment: "VoiceOver hint for delete-account row"
        )))
    }
}

#Preview {
    NavigationStack {
        PrivacyAndDataView()
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
