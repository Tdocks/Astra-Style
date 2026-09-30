//
//  StudioHomeView.swift
//  AstraStyle
//
//  Style Studio tab: gallery of generations plus the same Visualize door
//  Home and outfit detail already use. No preset mall.
//

import SwiftUI

struct StudioHomeView: View {
    @State private var viewModel: StudioHomeViewModel
    @Environment(AppRouter.self) private var router
    @State private var generationPendingDeletion: UUID?
    @State private var showsDeleteConfirmation = false

    init(viewModel: StudioHomeViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .tint(AstraColor.accentChampagne)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                failed(error)
            case .empty:
                empty
            case .loaded(let generations):
                gallery(generations)
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Style Studio", comment: "Studio tab title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.presentModal(.studioGeneration(outfitID: nil))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "See a look on you", comment: "Studio generate"))
                .accessibilityIdentifier("studio.start")
            }
        }
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
        .confirmationDialog(
            String(localized: "Delete this preview?", comment: "Confirmation before deleting a Studio preview"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete preview", comment: "Confirm Studio preview deletion"), role: .destructive) {
                guard let generationPendingDeletion else { return }
                Task { await viewModel.deleteGeneration(id: generationPendingDeletion) }
                self.generationPendingDeletion = nil
            }
            Button(String(localized: "Cancel", comment: "Cancel Studio preview deletion"), role: .cancel) {
                generationPendingDeletion = nil
            }
        } message: {
            Text(String(localized: "The saved image and its history will be removed.", comment: "Effect of deleting a Studio preview"))
        }
        .alert(
            String(localized: "That preview couldn't be deleted", comment: "Studio preview deletion failure title"),
            isPresented: deletionErrorIsPresented
        ) {
            Button(String(localized: "OK", comment: "Dismiss preview deletion error"), role: .cancel) {
                viewModel.clearDeletionError()
            }
        } message: {
            Text(viewModel.deletionError ?? "")
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text(String(
                localized: "See a look on you before you wear it.",
                comment: "Studio empty title"
            ))
            .astraText(.body)
            .foregroundStyle(AstraColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            AstraButton(
                title: String(localized: "See a look on you", comment: "Studio generate CTA")
            ) {
                router.presentModal(.studioGeneration(outfitID: nil))
            }
            .accessibilityIdentifier("studio.empty.start")
            Spacer()
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("studio.empty")
    }

    private func failed(_ error: AstraError) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text(error.message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
            Button(String(localized: "Try again", comment: "Studio retry")) {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.astraSecondary)
            Spacer()
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func gallery(_ generations: [StudioGeneration]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AstraSpacing.md) {
                ForEach(generations.filter { !$0.isDeleted }) { generation in
                    generationCard(generation)
                        .onAppear {
                            Task { await viewModel.loadMoreIfNeeded(after: generation.id) }
                        }
                }
                if viewModel.isLoadingMore {
                    ProgressView()
                        .tint(AstraColor.accentChampagne)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AstraSpacing.md)
                        .accessibilityLabel(Text("Loading more Studio previews", comment: "Gallery pagination progress"))
                } else if let paginationError = viewModel.paginationError {
                    VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                        Text(paginationError)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.destructive)
                        Button(String(localized: "Try again", comment: "Retry loading more Studio previews")) {
                            Task { await viewModel.loadNextPage() }
                        }
                        .buttonStyle(.astraSecondary)
                        .accessibilityIdentifier("studio.gallery.retry")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AstraSpacing.sm)
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("studio.gallery")
    }

    private func generationCard(_ generation: StudioGeneration) -> some View {
        AstraCard {
            HStack(spacing: AstraSpacing.md) {
                generationOpenButton(generation)
                generationDeleteControl(generation)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func generationOpenButton(_ generation: StudioGeneration) -> some View {
        Button {
            router.push(StudioRoute.generation(generationID: generation.id))
        } label: {
            HStack(spacing: AstraSpacing.md) {
                if generation.status == .complete {
                    AstraRemoteImage(
                        url: viewModel.imageURLs[generation.id],
                        aspectRatio: 4.0 / 5.0,
                        thumbnail: .listRowThumbnail,
                        accessibilityDescription: String(
                            localized: "Visual estimate from Style Studio",
                            comment: "Studio gallery image accessibility description"
                        )
                    )
                    .frame(width: 88)
                }
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(statusLabel(generation.status))
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                    Text(generation.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                    Text(String(localized: "Open estimate", comment: "Studio gallery card action"))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                }
                Spacer(minLength: AstraSpacing.xs)
                Image(systemName: "chevron.right")
                    .astraIcon(.disclosure)
                    .foregroundStyle(AstraColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("studio.generation.\(generation.id.uuidString)")
    }

    @ViewBuilder
    private func generationDeleteControl(_ generation: StudioGeneration) -> some View {
        if generation.status == .queued || generation.status == .generating {
            Text(String(localized: "Available after it finishes", comment: "Why an active Studio preview cannot be deleted"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        } else if viewModel.deletingIDs.contains(generation.id) {
            ProgressView()
                .tint(AstraColor.accentChampagne)
                .accessibilityLabel(Text(String(localized: "Deleting preview", comment: "VoiceOver status during preview deletion")))
        } else {
            Button(role: .destructive) {
                generationPendingDeletion = generation.id
                showsDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .astraIcon(.inline)
                    .foregroundStyle(AstraColor.destructive)
                    .padding(AstraSpacing.xs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.deletingIDs.isEmpty)
            .accessibilityLabel(Text(String(localized: "Delete preview", comment: "Delete one saved Style Studio preview")))
            .accessibilityIdentifier("studio.generation.delete.\(generation.id.uuidString)")
        }
    }

    private func statusLabel(_ status: StudioGenerationStatus) -> String {
        switch status {
        case .queued: String(localized: "Queued", comment: "Studio generation status")
        case .generating: String(localized: "Generating", comment: "Studio generation status")
        case .complete: String(localized: "Visual estimate", comment: "Studio generation status")
        case .failed: String(localized: "Didn't finish", comment: "Studio generation status")
        }
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
