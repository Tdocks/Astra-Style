//
//  ProfileIdentityCard.swift
//  AstraStyle
//
//  Private account identity and optional profile photo controls.
//

import PhotosUI
import SwiftUI

@MainActor
struct ProfileIdentityCard: View {
    @State private var viewModel: ProfileIdentityViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showsPhotoPicker = false
    @State private var showsRemoveConfirmation = false

    let canEdit: Bool

    init(viewModel: ProfileIdentityViewModel, canEdit: Bool) {
        _viewModel = State(wrappedValue: viewModel)
        self.canEdit = canEdit
    }

    var body: some View {
        AstraCard {
            switch viewModel.phase {
            case .loading:
                HStack(spacing: AstraSpacing.md) {
                    ProgressView().tint(AstraColor.accentChampagne)
                    Text(String(localized: "Loading your profile.", comment: "Profile identity loading"))
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            case .ready(let profile, let imageURL):
                identity(profile: profile, imageURL: imageURL)
            case .failed(let message):
                VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                    Text(message).astraText(.callout).foregroundStyle(AstraColor.textSecondary)
                    Button(String(localized: "Try again", comment: "Retry profile identity load")) {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.astraSecondary)
                }
            }
        }
        .task { await viewModel.refresh() }
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            Task {
                defer { selectedPhoto = nil }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else {
                        viewModel.notice = String(localized: "That photo couldn't be opened. Choose another one.", comment: "Photos picker returned no data")
                        return
                    }
                    await viewModel.saveAvatar(data)
                } catch {
                    viewModel.notice = String(localized: "That photo couldn't be opened. Choose another one.", comment: "Photos picker load failed")
                }
            }
        }
        .confirmationDialog(
            String(localized: "Remove your profile photo?", comment: "Avatar deletion confirmation title"),
            isPresented: $showsRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Remove photo", comment: "Confirm profile photo deletion"), role: .destructive) {
                Task { await viewModel.removeAvatar() }
            }
            Button(String(localized: "Cancel", comment: "Cancel profile photo removal"), role: .cancel) {}
        } message: {
            Text(String(localized: "Your photo will be removed from your profile and private storage.", comment: "Effect of deleting profile photo"))
        }
    }

    private func identity(profile: Profile, imageURL: URL?) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            HStack(spacing: AstraSpacing.md) {
                avatar(imageURL: imageURL, displayName: profile.displayName)
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(displayName(for: profile))
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                    if canEdit {
                        Button {
                            showsPhotoPicker = true
                        } label: {
                            Label(
                                String(localized: "Choose profile photo", comment: "Opens system photo picker"),
                                systemImage: "photo"
                            )
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.accentChampagneAccessible)
                            .frame(minHeight: AstraSize.minTapTarget, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .photosPicker(isPresented: $showsPhotoPicker, selection: $selectedPhoto, matching: .images)
                        .disabled(viewModel.isSaving)
                        .accessibilityIdentifier("profile.avatar.choose")
                    }
                }
                Spacer(minLength: 0)
                if viewModel.isSaving { ProgressView().tint(AstraColor.accentChampagne) }
            }
            if let notice = viewModel.notice {
                Text(notice)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.avatar.notice")
            }
            if canEdit, profile.avatarStoragePath != nil || profile.avatarURL != nil {
                Button(role: .destructive) {
                    showsRemoveConfirmation = true
                } label: {
                    Text(String(localized: "Remove profile photo", comment: "Opens profile photo deletion confirmation"))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.destructive)
                }
                .buttonStyle(.plain)
                .frame(minHeight: AstraSize.minTapTarget, alignment: .leading)
                .disabled(viewModel.isSaving)
                .accessibilityIdentifier("profile.avatar.remove")
            }
        }
        .accessibilityIdentifier("profile.identity")
    }

    private func displayName(for profile: Profile) -> String {
        let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
            ? String(localized: "Your style profile", comment: "Fallback profile name")
            : name
    }

    private func avatar(imageURL: URL?, displayName: String?) -> some View {
        ZStack {
            Circle().fill(AstraColor.surfaceElevated)
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initials(displayName)
                    }
                }
                .clipShape(Circle())
            } else {
                initials(displayName)
            }
        }
        .frame(width: 64, height: 64)
        .overlay(Circle().strokeBorder(AstraColor.divider, lineWidth: 1))
        .accessibilityLabel(Text(String(localized: "Profile photo", comment: "Profile avatar accessibility label")))
    }

    private func initials(_ name: String?) -> some View {
        Text(name?.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "A")
            .astraText(.headline)
            .foregroundStyle(AstraColor.accentChampagneAccessible)
    }
}
