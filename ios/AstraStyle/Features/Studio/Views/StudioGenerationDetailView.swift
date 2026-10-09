//
//  StudioGenerationDetailView.swift
//  AstraStyle
//
//  One saved generation from the Studio tab gallery.
//

import SwiftUI

struct StudioGenerationDetailView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppContainer.self) private var container
    @State private var showsCollections = false
    @State private var showsDescriptionEditor = false
    @State private var showsHighResolutionConfirmation = false
    @State private var viewModel: StudioGenerationDetailViewModel

    init(viewModel: StudioGenerationDetailViewModel) {
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
                VStack(alignment: .leading, spacing: AstraSpacing.md) {
                    Text(error.message)
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textSecondary)
                    Button(String(localized: "Try again", comment: "Retry loading a Studio estimate")) {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.astraSecondary)
                }
                .padding(AstraSpacing.pagePadding)
            case .loaded(let generation):
                ScrollView {
                    VStack(alignment: .leading, spacing: AstraSpacing.md) {
                        Text(String(
                            localized: "Visual estimate",
                            comment: "Studio result badge"
                        ))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                        Text(statusCopy(generation.status))
                            .astraText(.title2)
                            .foregroundStyle(AstraColor.textPrimary)
                        if let message = generation.errorMessage {
                            Text(message)
                                .astraText(.callout)
                                .foregroundStyle(AstraColor.textSecondary)
                        }
                        if let url = viewModel.resultImageURL {
                            GeneratedImageContainer(accessibilityDescription: generation.imageDescription) {
                                AstraRemoteImage(url: url, aspectRatio: 2.0 / 3.0, contentMode: .fit,
                                                 accessibilityDescription: generation.imageDescription)
                                    .accessibilityIdentifier("studio.detail.image")
                            }
                            .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
                        }
                        if generation.status == .complete && viewModel.canExportHighResolution {
                            highResolutionAction
                        }
                        if let child = viewModel.highResolutionChild {
                            highResolutionChildSection(child)
                        }
                        if let error = viewModel.highResolutionError, viewModel.highResolutionChild == nil {
                            Text(error).astraText(.callout).foregroundStyle(AstraColor.textSecondary)
                        }
                        if generation.status == .complete && !generation.referenceImagePath.isEmpty {
                            Button("Compare with original") {
                                router.push(StudioRoute.compare(generationIDs: [generation.id]))
                            }
                            .buttonStyle(.astraSecondary)
                            .accessibilityIdentifier("studio.detail.compare")
                        }
                        if generation.status == .complete {
                            Button("Edit image description") {
                                viewModel.descriptionDraft = generation.altDescription ?? generation.imageDescription
                                showsDescriptionEditor = true
                            }
                            .buttonStyle(.astraSecondary)
                            .accessibilityIdentifier("studio.detail.editDescription")
                            .sheet(isPresented: $showsDescriptionEditor) { descriptionEditor }
                            Button("Save to collection") { showsCollections = true }
                                .buttonStyle(.astraSecondary)
                                .accessibilityIdentifier("studio.detail.save")
                                .sheet(isPresented: $showsCollections) {
                                    NavigationStack {
                                        StudioLookbooksView(viewModel: StudioLookbooksViewModel(
                                            repository: container.studioRepository, generationID: generation.id
                                        ))
                                    }
                                }
                            if let exportURL = viewModel.exportURL {
                                ShareLink(item: exportURL, subject: Text("Astra Style visual estimate"),
                                          message: Text("AI visual estimate. Fit, colors and garment details may differ.")) {
                                    Label("Share estimate", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.astraSecondary)
                                .accessibilityIdentifier("studio.detail.share")
                            } else {
                                Button(viewModel.isExporting ? "Preparing image…" : "Prepare image to share") {
                                    Task { await viewModel.prepareExport() }
                                }
                                .buttonStyle(.astraSecondary)
                                .disabled(viewModel.isExporting)
                                .accessibilityIdentifier("studio.detail.export")
                            }
                            if let error = viewModel.exportError {
                                Text(error).astraText(.callout).foregroundStyle(AstraColor.textSecondary)
                            }
                        }
                        if generation.isRetryableWithoutCharge {
                            Button(String(localized: "Try again", comment: "Retry a provider-failed Studio estimate")) {
                                Task { await viewModel.retry() }
                            }
                            .buttonStyle(.astraSecondary)
                            .accessibilityIdentifier("studio.detail.retry")
                        }
                    }
                    .padding(AstraSpacing.pagePadding)
                }
                .refreshable { await viewModel.refresh() }
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Estimate", comment: "Studio generation detail"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .alert("Export a high-resolution estimate?", isPresented: $showsHighResolutionConfirmation) {
            Button("Cancel", role: .cancel) { viewModel.cancelHighResolutionExportConfirmation() }
            Button(viewModel.highResolutionConfirmationActionTitle) {
                Task {
                    await viewModel.confirmHighResolutionExport()
                    showsHighResolutionConfirmation = viewModel.hasPendingHighResolutionConfirmation
                }
            }
            .disabled(viewModel.isExportingHighResolution)
        } message: {
            Text(viewModel.highResolutionConfirmationMessage)
        }
    }

    private var highResolutionAction: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Button {
                Task {
                    await viewModel.prepareHighResolutionExport()
                    showsHighResolutionConfirmation = viewModel.hasPendingHighResolutionConfirmation
                }
            } label: {
                Label(
                    viewModel.isPreparingHighResolutionExport ? "Checking allowance…" : "Export high resolution",
                    systemImage: "arrow.up.right"
                )
            }
            .buttonStyle(.astraSecondary)
            .disabled(viewModel.isPreparingHighResolutionExport || viewModel.isExportingHighResolution)
            .accessibilityIdentifier("studio.detail.exportHiRes")
            if viewModel.isExportingHighResolution {
                ProgressView("Preparing high-resolution export…")
                    .tint(AstraColor.accentChampagne)
            }
        }
    }

    private func highResolutionChildSection(_ child: StudioGeneration) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text("High resolution export")
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
            Text(statusCopy(child.status))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
            if let url = viewModel.highResolutionImageURL {
                GeneratedImageContainer(accessibilityDescription: child.imageDescription) {
                    AstraRemoteImage(url: url, aspectRatio: 2.0 / 3.0, contentMode: .fit,
                                     accessibilityDescription: child.imageDescription)
                        .accessibilityIdentifier("studio.detail.exportHiRes.image")
                }
                .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
            }
            if let message = child.errorMessage {
                Text(message).astraText(.callout).foregroundStyle(AstraColor.textSecondary)
            }
            if let error = viewModel.highResolutionError {
                Text(error).astraText(.callout).foregroundStyle(AstraColor.textSecondary)
                Button(child.isRetryableWithoutCharge ? "Retry high-resolution export" : "Check export status") {
                    Task {
                        if child.isRetryableWithoutCharge {
                            await viewModel.retryHighResolutionExport()
                        } else {
                            await viewModel.refreshHighResolutionExport()
                        }
                    }
                }
                .buttonStyle(.astraSecondary)
                .disabled(viewModel.isExportingHighResolution)
            } else if child.isRetryableWithoutCharge {
                Button("Retry high-resolution export") { Task { await viewModel.retryHighResolutionExport() } }
                    .buttonStyle(.astraSecondary)
                    .disabled(viewModel.isExportingHighResolution)
            }
        }
        .padding(AstraSpacing.md)
        .background(AstraColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
    }

    private func statusCopy(_ status: StudioGenerationStatus) -> String {
        switch status {
        case .queued: String(localized: "Queued", comment: "Studio generation status")
        case .generating: String(localized: "Generating", comment: "Studio generation status")
        case .complete: String(localized: "This is a visual estimate, not a photograph.", comment: "Studio result disclaimer")
        case .failed: String(localized: "Didn't finish", comment: "Studio generation status")
        }
    }

    private var descriptionEditor: some View {
        NavigationStack {
            Form {
                Section("Image description") {
                    TextField("Describe the outfit", text: $viewModel.descriptionDraft, axis: .vertical)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("studio.description.text")
                    Text("VoiceOver reads this description. Clear the field to restore the automatic description.")
                        .foregroundStyle(AstraColor.textSecondary)
                    Button("Restore automatic description") { viewModel.descriptionDraft = "" }
                        .accessibilityIdentifier("studio.description.reset")
                    if let error = viewModel.descriptionError { Text(error).foregroundStyle(AstraColor.textSecondary) }
                }
            }
            .navigationTitle("Image description")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showsDescriptionEditor = false }.disabled(viewModel.isSavingDescription)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isSavingDescription ? "Saving…" : "Save") {
                        Task { if await viewModel.saveImageDescription() { showsDescriptionEditor = false } }
                    }
                    .disabled(viewModel.isSavingDescription)
                    .accessibilityIdentifier("studio.description.save")
                }
            }
        }
    }
}
