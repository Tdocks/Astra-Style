//
//  PublicLookDetailView.swift
//  AstraStyle
//
//  Read-only detail for another user's voluntarily shared, worn look. It only
//  renders sanitized summary and garment data and offers the report action.
//

import SwiftUI

struct PublicLookDetailView: View {
    @State private var viewModel: PublicLookDetailViewModel
    @State private var isReportConfirmationPresented = false
    @State private var reportMessage: String?

    init(viewModel: PublicLookDetailViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                content
            }
            .padding(AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
        .confirmationDialog(
            Text("Report this look?", comment: "Confirm reporting a public look"),
            isPresented: $isReportConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Report look", comment: "Report public look action"), role: .destructive) {
                Task {
                    do {
                        try await viewModel.report()
                        reportMessage = String(localized: "Thanks. This look was reported.", comment: "Look report confirmation")
                    } catch {
                        reportMessage = String(localized: "Couldn't report that look. Please try again.", comment: "Look report error")
                    }
                }
            }
            Button(String(localized: "Cancel", comment: "Cancel public look report"), role: .cancel) {}
        } message: {
            Text("We'll review it against our community guidelines.", comment: "Report public look explanation")
        }
        .alert(
            Text("Lookbook", comment: "Public look report result title"),
            isPresented: Binding(
                get: { reportMessage != nil },
                set: { if !$0 { reportMessage = nil } }
            )
        ) {
            Button(String(localized: "Done", comment: "Dismiss public look report result")) {
                reportMessage = nil
            }
        } message: {
            Text(reportMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .tint(AstraColor.accentChampagne)
                .frame(maxWidth: .infinity, minHeight: 240)
                .accessibilityLabel(Text("Loading shared look", comment: "Public look detail loading"))
        case .failed(let error):
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                Text(error.message)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
                Button(String(localized: "Try again", comment: "Retry public look loading")) {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.astraSecondary)
            }
        case .loaded(let look, let garments):
            loaded(look, garments: garments)
        }
    }

    private func loaded(_ look: PublicWornLook, garments: [LookGarment]) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            Text(look.name)
                .astraText(.title1)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            silhouette(garments)
            description(look.description)
            occasionTags(look.occasionTags)
            garmentSection(garments)
            reportButton
        }
    }

    @ViewBuilder
    private func silhouette(_ garments: [LookGarment]) -> some View {
        if !garments.isEmpty {
            LookSilhouetteView(garments: garments, frame: .unknown, onTapGarment: nil)
                .frame(maxHeight: AstraSize.silhouetteHeight)
                .accessibilityIdentifier("discover.publicLook.silhouette")
        }
    }

    @ViewBuilder
    private func description(_ value: String?) -> some View {
        if let value, !value.isEmpty {
            Text(value)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func occasionTags(_ values: [String]) -> some View {
        if !values.isEmpty {
            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                ForEach(values, id: \.self) { tag in
                    Text(tag)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                        .padding(.horizontal, AstraSpacing.md)
                        .padding(.vertical, AstraSpacing.xs)
                        .frame(minHeight: AstraSize.minTapTarget)
                        .background(AstraColor.surfaceElevated, in: Capsule())
                }
            }
        }
    }

    private func garmentSection(_ garments: [LookGarment]) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text("Pieces in this look")
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(garments) { garment in
                garmentRow(garment)
            }
        }
    }

    private func garmentRow(_ garment: LookGarment) -> some View {
        HStack(spacing: AstraSpacing.md) {
            AstraRemoteImage(
                url: garment.imageURL,
                aspectRatio: 1,
                thumbnail: .listRowThumbnail,
                showsBackground: false,
                contentMode: .fit,
                accessibilityDescription: garment.item.name
            )
            .frame(width: 56)
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(garment.item.name)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textPrimary)
                if let brand = garment.item.brand, !brand.isEmpty {
                    Text(brand)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AstraSpacing.sm)
        .background(AstraColor.surfaceElevated, in: RoundedRectangle(cornerRadius: AstraRadius.card))
    }

    private var reportButton: some View {
        Button(String(localized: "Report this look", comment: "Open report dialog for a public look")) {
            isReportConfirmationPresented = true
        }
        .buttonStyle(.astraTertiary)
        .disabled(viewModel.isReporting)
        .accessibilityIdentifier("discover.publicLook.report")
    }
}
