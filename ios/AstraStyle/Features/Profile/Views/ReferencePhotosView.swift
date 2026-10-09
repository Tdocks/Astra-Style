//
//  ReferencePhotosView.swift
//  AstraStyle
//
//  Lets users inspect and remove the optional photos they supplied for
//  personal Style Studio previews.
//

import SwiftUI

struct ReferencePhotosView: View {
    @State private var viewModel: ReferencePhotosViewModel
    @State private var photoPendingDeletion: SavedReferencePhoto?
    @State private var showsDeleteConfirmation = false

    init(viewModel: ReferencePhotosViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                AstraSectionHeader(
                    title: String(localized: "Reference Photos", comment: "Reference photo privacy screen title")
                )
                .accessibilityAddTraits(.isHeader)
                explanation
                removalStatus
                content
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Reference Photos", comment: "Reference photo navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
        .confirmationDialog(
            String(localized: "Remove this reference photo?", comment: "Confirmation before deleting a reference photo"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Remove photo and previews", comment: "Confirm deletion of reference photo and related previews"), role: .destructive) {
                guard let photoPendingDeletion else { return }
                Task { await viewModel.deleteReferencePhoto(path: photoPendingDeletion.path) }
                self.photoPendingDeletion = nil
            }
            .accessibilityIdentifier("profile.referencePhotos.confirmDelete")
            Button(String(localized: "Cancel", comment: "Cancel reference photo deletion"), role: .cancel) {
                photoPendingDeletion = nil
            }
        } message: {
            Text(String(
                localized: "The photo and every preview or variation made from it will be removed from your profile and saved looks. File removal may finish in the background.",
                comment: "Effect of deleting a reference photo"
            ))
        }
        .alert(
            String(localized: "That photo couldn't be removed", comment: "Reference photo deletion failure title"),
            isPresented: deletionErrorIsPresented
        ) {
            Button(String(localized: "OK", comment: "Dismiss reference photo deletion error"), role: .cancel) {
                viewModel.clearDeletionError()
            }
        } message: {
            Text(viewModel.deletionError ?? "")
        }
    }

    private var explanation: some View {
        Text(String(
            localized: "Your reference photo is optional. Remove it here at any time. Removing it also deletes Style Studio previews made with it; your closet photos are not affected.",
            comment: "Explanation of personal reference photo storage and deletion"
        ))
        .astraText(.callout)
        .foregroundStyle(AstraColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var removalStatus: some View {
        if viewModel.pendingImageDeletionCount > 0 || viewModel.removalStatusError != nil {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(viewModel.removalStatusError ?? String(localized: "Photo or preview removal is in progress. We'll retry automatically.", comment: "Pending private image removal"))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Check image removal", comment: "Refresh tracked image removal status")) {
                    Task { await viewModel.refreshRemovalStatus() }
                }
                .buttonStyle(.astraSecondary)
                .disabled(viewModel.isCheckingRemoval)
                .accessibilityIdentifier("profile.referencePhotos.checkRemoval")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("profile.referencePhotos.pendingRemoval")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .tint(AstraColor.accentChampagne)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("profile.referencePhotos.loading")
        case .loaded(let photos):
            VStack(spacing: AstraSpacing.md) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { entry in
                    photoCard(entry.element, number: entry.offset + 1)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("profile.referencePhotos.list")
        case .empty:
            emptyState
        case .failed(let message):
            failureState(message)
        }
    }

    private func photoCard(_ photo: SavedReferencePhoto, number: Int) -> some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                photoHeader(photo, number: number)

                if photo.isUsedByActivePreview {
                    Label(
                        String(localized: "A preview is in progress. Try again when it finishes.", comment: "Why a reference photo cannot be deleted during generation"),
                        systemImage: "hourglass"
                    )
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.warningAmber)
                } else if viewModel.deletingPaths.contains(photo.path) {
                    ProgressView(String(localized: "Removing photo and previews…", comment: "Progress during reference photo deletion"))
                        .tint(AstraColor.accentChampagne)
                        .accessibilityIdentifier("profile.referencePhotos.deleting")
                } else {
                    Button(role: .destructive) {
                        photoPendingDeletion = photo
                        showsDeleteConfirmation = true
                    } label: {
                        Label(
                            String(localized: "Remove photo and previews", comment: "Remove one personal reference photo"),
                            systemImage: "trash"
                        )
                    }
                    .buttonStyle(.astraSecondary)
                    .disabled(!viewModel.deletingPaths.isEmpty)
                    .accessibilityIdentifier("profile.referencePhotos.delete.\(number)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func photoHeader(_ photo: SavedReferencePhoto, number: Int) -> some View {
        HStack(alignment: .top, spacing: AstraSpacing.md) {
            photoImage(for: photo)
                .frame(width: AstraSize.referencePhotoWidth, height: AstraSize.referencePhotoHeight)
                .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card))

            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                Text(String(
                    localized: "Reference photo \(number)",
                    comment: "Label for one saved personal reference photo"
                ))
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)

                if photo.previewCount > 0 {
                    Text(String(
                        localized: "Removing this also deletes \(photo.previewCount) saved Studio previews.",
                        comment: "Number of saved previews that will be removed with this photo"
                    ))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(localized: "No saved previews use this photo.", comment: "Reference photo with no Studio previews"))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func photoImage(for photo: SavedReferencePhoto) -> some View {
        if let url = viewModel.imageURLs[photo.path] {
            AstraRemoteImage(
                url: url,
                aspectRatio: 4.0 / 5.0,
                thumbnail: .listRowThumbnail,
                accessibilityDescription: String(localized: "Your Style Studio reference photo", comment: "Reference photo accessibility description")
            )
        } else {
            Image(systemName: "person.crop.rectangle")
                .resizable()
                .scaledToFit()
                .padding(AstraSpacing.lg)
                .foregroundStyle(AstraColor.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AstraColor.surfaceElevated)
                .accessibilityLabel(Text(String(localized: "Reference photo preview unavailable", comment: "Fallback reference photo accessibility label")))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Image(systemName: "person.crop.rectangle")
                .astraIcon(.feature)
                .foregroundStyle(AstraColor.accentChampagne)
            Text(String(localized: "No reference photos saved", comment: "Empty state title for reference photos"))
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
            Text(String(
                localized: "You can still use your closet and get daily outfit help without adding a personal photo.",
                comment: "Empty state explanation for reference photos"
            ))
            .astraText(.callout)
            .foregroundStyle(AstraColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.lg)
        .background(AstraColor.surfaceElevated, in: RoundedRectangle(cornerRadius: AstraRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.referencePhotos.empty")
    }

    private func failureState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(String(localized: "Your reference photos didn't load", comment: "Reference photo load failure title"))
                .astraText(.headline)
                .foregroundStyle(AstraColor.warningAmber)
            Text(message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
            Button(String(localized: "Try again", comment: "Retry loading reference photos")) {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("profile.referencePhotos.retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.lg)
        .background(AstraColor.surfaceElevated, in: RoundedRectangle(cornerRadius: AstraRadius.card))
        .accessibilityIdentifier("profile.referencePhotos.failure")
    }

    private var deletionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.deletionError != nil },
            set: { isPresented in
                if !isPresented { viewModel.clearDeletionError() }
            }
        )
    }
}
