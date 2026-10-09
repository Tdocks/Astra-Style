//
//  PrivacyAndDataView.swift
//  AstraStyle
//
//  Privacy controls for style memories, reference photos, personal data export,
//  and account deletion (spec section 29).
//

import SwiftUI

struct PrivacyAndDataView: View {
    @Environment(AppRouter.self) private var router
    @State private var exportViewModel: PersonalDataExportViewModel

    init(exportViewModel: PersonalDataExportViewModel) {
        _exportViewModel = State(wrappedValue: exportViewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                AstraSectionHeader(
                    title: String(localized: "Privacy & Data", comment: "Privacy and data controls screen title")
                )
                .accessibilityAddTraits(.isHeader)

                styleMemoriesRow
                referencePhotosRow
                exportRow
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

    private var exportRow: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(String(localized: "Your personal data", comment: "Title for personal data export"))
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                Text(String(
                    localized: "Create a JSON copy of your profile, closet, outfits, activity, and Kyra conversations. Save or share the file somewhere private.",
                    comment: "Description of the personal data export contents"
                ))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                switch exportViewModel.state {
                case .ready:
                    exportButton
                case .exporting:
                    HStack(spacing: AstraSpacing.sm) {
                        ProgressView()
                            .tint(AstraColor.accentChampagne)
                        Text(String(localized: "Preparing your export…", comment: "Personal data export progress"))
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                case .available(let url):
                    HStack(spacing: AstraSpacing.sm) {
                        ShareLink(item: url) {
                            Label(
                                String(localized: "Save or share file", comment: "Open iOS share sheet for personal data export"),
                                systemImage: "square.and.arrow.up"
                            )
                            .astraText(.callout)
                            .foregroundStyle(AstraColor.accentChampagneAccessible)
                        }
                        .accessibilityIdentifier("privacyAndData.export.share")

                        Button(String(localized: "Create again", comment: "Create a refreshed personal data export")) {
                            Task { await exportViewModel.createExport() }
                        }
                        .buttonStyle(.astraSecondary)
                        .accessibilityIdentifier("privacyAndData.export.retry")
                    }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                        Text(message)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.destructive)
                        exportButton
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    private var exportButton: some View {
        Button {
            Task { await exportViewModel.createExport() }
        } label: {
            Label(
                String(localized: "Create data export", comment: "Start building a personal data export"),
                systemImage: "arrow.down.doc"
            )
            .astraText(.callout)
            .foregroundStyle(AstraColor.accentChampagneAccessible)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("privacyAndData.export.create")
    }

    private var styleMemoriesRow: some View {
        Button {
            router.push(ProfileRoute.styleMemories)
        } label: {
            AstraCard {
                HStack(spacing: AstraSpacing.md) {
                    VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                        Text(String(localized: "Style Memories", comment: "Row opening Kyra's saved style memories"))
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.textPrimary)
                        Text(String(
                            localized: "Review or remove notes Kyra uses for personal advice.",
                            comment: "Subtitle under Style Memories"
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
        .accessibilityIdentifier("privacyAndData.styleMemoriesRow")
        .accessibilityHint(Text(String(localized: "Opens the notes Kyra has saved about your style", comment: "VoiceOver hint for Style Memories row")))
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

    private var referencePhotosRow: some View {
        Button {
            router.push(ProfileRoute.referencePhotos)
        } label: {
            AstraCard {
                HStack(spacing: AstraSpacing.md) {
                    VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                        Text(String(localized: "Reference Photos", comment: "Row opening saved personal reference photos"))
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.textPrimary)
                        Text(String(
                            localized: "Review or remove photos and Studio previews made with them.",
                            comment: "Subtitle under Reference Photos"
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
        .accessibilityIdentifier("privacyAndData.referencePhotosRow")
        .accessibilityHint(Text(String(localized: "Opens saved personal reference photos", comment: "VoiceOver hint for Reference Photos row")))
    }
}

#Preview {
    NavigationStack {
        PrivacyAndDataView(
            exportViewModel: PersonalDataExportViewModel(profileRepository: MockProfileRepository())
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
