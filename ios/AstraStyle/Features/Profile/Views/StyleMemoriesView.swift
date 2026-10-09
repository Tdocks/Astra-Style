//
//  StyleMemoriesView.swift
//  AstraStyle
//
//  The user-facing inspect/delete surface for Kyra's durable style notes.
//

import SwiftUI

struct StyleMemoriesView: View {
    @State private var viewModel: StyleMemoriesViewModel
    @State private var memoryPendingDeletion: StyleMemory?
    @State private var showsDeleteConfirmation = false

    init(viewModel: StyleMemoriesViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                AstraSectionHeader(
                    title: String(localized: "Style Memories", comment: "Style memories screen title")
                )
                .accessibilityAddTraits(.isHeader)

                Text(String(
                    localized: "These are the style notes Kyra uses to make her advice more personal. Remove any note you no longer want her to use.",
                    comment: "Explanation of user-visible Kyra memories"
                ))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                content
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Style Memories", comment: "Style memories navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
        .confirmationDialog(
            String(localized: "Remove this style note?", comment: "Confirmation before deleting a style memory"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete memory", comment: "Confirm style memory deletion"), role: .destructive) {
                guard let memoryPendingDeletion else { return }
                Task { await viewModel.deleteMemory(id: memoryPendingDeletion.id) }
                self.memoryPendingDeletion = nil
            }
            Button(String(localized: "Cancel", comment: "Cancel style memory deletion"), role: .cancel) {
                memoryPendingDeletion = nil
            }
        } message: {
            Text(String(
                localized: "Kyra will stop using this note in future advice.",
                comment: "Effect of deleting a style memory"
            ))
        }
        .alert(
            String(localized: "That note couldn't be deleted", comment: "Style memory deletion failure title"),
            isPresented: deletionErrorIsPresented
        ) {
            Button(String(localized: "OK", comment: "Dismiss style memory deletion error"), role: .cancel) {
                viewModel.clearDeletionError()
            }
        } message: {
            Text(viewModel.deletionError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .tint(AstraColor.accentChampagne)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("profile.styleMemories.loading")
        case .loaded(let memories):
            VStack(spacing: AstraSpacing.sm) {
                ForEach(memories) { memory in
                    memoryRow(memory)
                }
            }
            .accessibilityIdentifier("profile.styleMemories.list")
        case .empty:
            emptyState
        case .failed(let message):
            failureState(message)
        }
    }

    private func memoryRow(_ memory: StyleMemory) -> some View {
        AstraCard {
            HStack(alignment: .top, spacing: AstraSpacing.md) {
                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    Text(memoryTypeLabel(memory.memoryType))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                    Text(memory.content)
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(memory.createdAt, style: .date)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                }
                Spacer(minLength: AstraSpacing.xs)
                if viewModel.deletingIDs.contains(memory.id) {
                    ProgressView()
                        .tint(AstraColor.accentChampagne)
                        .accessibilityLabel(Text(String(localized: "Deleting memory", comment: "VoiceOver status during deletion")))
                } else {
                    Button(role: .destructive) {
                        memoryPendingDeletion = memory
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
                    .accessibilityLabel(Text(String(localized: "Delete style note", comment: "Delete one Kyra memory")))
                    .accessibilityIdentifier("profile.styleMemories.delete.\(memory.id.uuidString)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.styleMemories.row.\(memory.id.uuidString)")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Image(systemName: "bookmark")
                .astraIcon(.feature)
                .foregroundStyle(AstraColor.accentChampagne)
            Text(String(localized: "Nothing saved yet", comment: "Empty state for user-visible style memories"))
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
            Text(String(
                localized: "As Kyra learns your preferences, the notes she saves will appear here.",
                comment: "Explanation of empty style memories"
            ))
            .astraText(.callout)
            .foregroundStyle(AstraColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.lg)
        .background(AstraColor.surfaceElevated, in: RoundedRectangle(cornerRadius: AstraRadius.card))
        .accessibilityIdentifier("profile.styleMemories.empty")
    }

    private func failureState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(String(localized: "Your notes didn't load", comment: "Style memory load failure title"))
                .astraText(.headline)
                .foregroundStyle(AstraColor.warningAmber)
            Text(message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
            Button(String(localized: "Try again", comment: "Retry loading style memories")) {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("profile.styleMemories.retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.lg)
        .background(AstraColor.surfaceElevated, in: RoundedRectangle(cornerRadius: AstraRadius.card))
        .accessibilityIdentifier("profile.styleMemories.failure")
    }

    private var deletionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.deletionError != nil },
            set: { isPresented in
                if !isPresented { viewModel.clearDeletionError() }
            }
        )
    }

    private func memoryTypeLabel(_ type: StyleMemoryType) -> String {
        switch type {
        case .preference:
            String(localized: "Preference", comment: "Style memory category")
        case .dislike:
            String(localized: "Avoid", comment: "Style memory category")
        case .fitNote:
            String(localized: "Fit note", comment: "Style memory category")
        case .brandAffinity:
            String(localized: "Brand", comment: "Style memory category")
        case .budgetNote:
            String(localized: "Budget", comment: "Style memory category")
        case .sizingNote:
            String(localized: "Sizing", comment: "Style memory category")
        case .general:
            String(localized: "Style note", comment: "Style memory category")
        }
    }
}
