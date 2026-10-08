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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var generationPendingDeletion: UUID?
    @State private var showsDeleteConfirmation = false
    @State private var isSelectingComparison = false
    @State private var comparisonIDs: [UUID] = []

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
        .safeAreaInset(edge: .top) {
            if viewModel.pendingImageDeletionCount > 0 || viewModel.cleanupStatusError != nil {
                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    Text(viewModel.cleanupStatusError ?? String(localized: "Image removal is in progress. We'll retry automatically."))
                        .astraText(.callout).foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(viewModel.isCheckingCleanup ? "Checking…" : "Check image removal") {
                        Task { await viewModel.refreshCleanupStatus() }
                    }
                    .buttonStyle(.astraSecondary).disabled(viewModel.isCheckingCleanup)
                    .accessibilityIdentifier("studio.cleanup.check")
                }
                .padding(AstraSpacing.pagePadding).frame(maxWidth: .infinity, alignment: .leading)
                .background(AstraColor.surfaceElevated)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("studio.cleanup.status")
            }
        }
        .navigationTitle(String(localized: "Style Studio", comment: "Studio tab title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isSelectingComparison {
                    Button("Compare \(comparisonIDs.count)") {
                        router.push(StudioRoute.compare(generationIDs: comparisonIDs))
                    }
                    .disabled(comparisonIDs.count != 2)
                    .accessibilityIdentifier("studio.compare.open")
                    Button("Cancel") { isSelectingComparison = false; comparisonIDs = [] }
                } else {
                    Button("Saved looks", systemImage: "books.vertical") { router.push(StudioRoute.lookbook) }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("studio.lookbooks.open")
                    Button("Compare") { isSelectingComparison = true; comparisonIDs = [] }
                        .disabled(!canCompare)
                        .accessibilityIdentifier("studio.compare.select")
                }
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
        .onChange(of: router.selectedTab) { _, tab in
            if tab == .studio { Task { await viewModel.refresh() } }
        }
        .onChange(of: router.presentedModal?.id) { previous, current in
            if previous != nil && current == nil { Task { await viewModel.refresh() } }
        }
        .onChange(of: availableComparisonIDs) { _, ids in comparisonIDs.removeAll { !ids.contains($0) } }
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
            .accessibilityIdentifier("studio.delete.confirm")
            Button(String(localized: "Cancel", comment: "Cancel Studio preview deletion"), role: .cancel) {
                generationPendingDeletion = nil
            }
        } message: {
            Text(String(localized: "This removes the image, its history, and its saved-collection entries. If another variation uses it, remove that variation first. File removal may finish in the background.", comment: "Effect of deleting a Studio preview"))
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
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                Text(String(localized: "See a look on you before you wear it.", comment: "Studio empty title"))
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    router.presentModal(.studioGeneration(outfitID: nil))
                } label: {
                    Text(String(localized: "See a look on you", comment: "Studio generate CTA"))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, AstraSpacing.sm)
                }
                .buttonStyle(.astraPrimary)
                .accessibilityIdentifier("studio.empty.start")
            }
            .padding(AstraSpacing.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("studio.empty")
        }
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
            if isSelectingComparison {
                guard generation.status == .complete else { return }
                if comparisonIDs.contains(generation.id) { comparisonIDs.removeAll { $0 == generation.id } }
                else if comparisonIDs.count < 2 { comparisonIDs.append(generation.id) }
            } else {
                router.push(StudioRoute.generation(generationID: generation.id))
            }
        } label: {
            HStack(spacing: AstraSpacing.md) {
                if isSelectingComparison {
                    Image(systemName: comparisonIDs.contains(generation.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                        .accessibilityLabel(comparisonIDs.contains(generation.id) ? "Selected for comparison" : "Not selected")
                }
                if generation.status == .complete && !isSelectingComparison && !dynamicTypeSize.isAccessibilitySize {
                    GeneratedImageContainer(accessibilityDescription: generation.imageDescription,
                                            disclosurePlacement: .below) {
                        AstraRemoteImage(
                        url: viewModel.imageURLs[generation.id],
                        aspectRatio: 4.0 / 5.0,
                        thumbnail: .listRowThumbnail,
                        accessibilityDescription: String(
                            localized: "Visual estimate from Style Studio",
                            comment: "Studio gallery image accessibility description"
                        )
                        )
                    }
                    .frame(width: 112)
                }
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(statusLabel(generation.status))
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                    Text(generation.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                    Text(isSelectingComparison ? "Select for comparison" : String(localized: "Open estimate", comment: "Studio gallery card action"))
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
        .disabled(isSelectingComparison && generation.status != .complete)
        .accessibilityValue(isSelectingComparison && comparisonIDs.contains(generation.id) ? "Selected" : "Not selected")
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

    private var availableComparisonIDs: Set<UUID> {
        guard case .loaded(let generations) = viewModel.state else { return [] }
        return Set(generations.filter { !$0.isDeleted && $0.status == .complete }.map(\.id))
    }

    private var canCompare: Bool {
        guard case .loaded(let generations) = viewModel.state else { return false }
        return generations.filter { !$0.isDeleted && $0.status == .complete }.count >= 2
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
