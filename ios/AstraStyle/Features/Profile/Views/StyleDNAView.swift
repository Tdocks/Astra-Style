//
//  StyleDNAView.swift
//  AstraStyle
//
//  Post-onboarding Style DNA. Reuses §6.10 section renderers.
//

import SwiftUI

struct StyleDNAView: View {
    @State private var viewModel: StyleDNAViewModel

    init(viewModel: StyleDNAViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                switch viewModel.phase {
                case .loading:
                    workingState
                case .ready(let dna):
                    result(dna, isRegenerating: false)
                case .regenerating(let dna):
                    result(dna, isRegenerating: true)
                case .failed(let message, let previous):
                    failureNotice(message)
                    if let previous {
                        result(previous, isRegenerating: false)
                    }
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Style DNA", comment: "Style DNA screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.regenerate() }
    }

    private var workingState: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            ProgressView()
                .tint(AstraColor.accentChampagne)
            Text(String(localized: "Reading your answers.", comment: "Style DNA loading"))
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("profile.styleDNA.loading")
    }

    private func failureNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(String(localized: "That didn't come back.", comment: "Style DNA failure title"))
                .astraText(.headline)
                .foregroundStyle(AstraColor.warningAmber)
            Text(message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
            Button(String(localized: "Try again", comment: "Retry Style DNA")) {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.astraSecondary)
        }
        .padding(AstraSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .fill(AstraColor.surfaceElevated)
        )
    }

    @ViewBuilder
    private func result(_ dna: StyleDNA, isRegenerating: Bool) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxl) {
            if isRegenerating {
                HStack(spacing: AstraSpacing.sm) {
                    ProgressView().tint(AstraColor.accentChampagne)
                    Text(String(localized: "Reading your new picks.", comment: "Style DNA regenerating"))
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                }
            }

            identitySection(dna)

            if !dna.secondaryInfluences.isEmpty {
                influencesSection(dna.secondaryInfluences)
            }

            if !dna.palette.preferredColors.isEmpty
                || !dna.palette.avoidedColors.isEmpty
                || !dna.palette.rationale.isEmpty {
                StyleDNAPaletteSection(palette: dna.palette)
            }

            if !dna.silhouette.headline.isEmpty || !dna.silhouette.detail.isEmpty {
                silhouetteSection(dna.silhouette)
            }

            if !dna.signatureOpportunities.isEmpty {
                signatureSection(dna.signatureOpportunities)
            }

            if !dna.wardrobePriorities.isEmpty {
                prioritySection(dna.wardrobePriorities)
            }

            if !dna.knownInputs.isEmpty || !dna.openQuestions.isEmpty || !dna.measuredDimensions.isEmpty {
                StyleDNAHonestySection(
                    knownInputs: dna.knownInputs,
                    openQuestions: dna.openQuestions,
                    measuredDimensions: dna.measuredDimensions
                )
            }

            Button(String(localized: "Refresh from my answers", comment: "Regenerate Style DNA")) {
                Task { await viewModel.regenerate() }
            }
            .buttonStyle(.astraSecondary)
            .disabled(viewModel.isWorking)
            .accessibilityIdentifier("profile.styleDNA.regenerate")
        }
        .opacity(isRegenerating ? 0.45 : 1)
        .allowsHitTesting(!isRegenerating)
    }

    @ViewBuilder
    private func identitySection(_ dna: StyleDNA) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            if let identity = dna.primaryIdentity {
                Text(String(localized: "YOUR DIRECTION", comment: "Style DNA eyebrow"))
                    .astraText(.micro)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                Text(identity.displayName)
                    .astraText(.displayL)
                    .foregroundStyle(AstraColor.textPrimary)
                    .accessibilityIdentifier("profile.styleDNA.identity")
            } else {
                Text(String(localized: "Kyra hasn't called a direction yet.", comment: "Style DNA no identity"))
                    .astraText(.title1)
                    .foregroundStyle(AstraColor.textPrimary)
            }
            if !dna.summary.isEmpty {
                Text(dna.summary)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func influencesSection(_ influences: [StyleIdentity]) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(
                title: String(localized: "Also in the mix", comment: "Style DNA section title"),
                eyebrow: String(localized: "SECONDARY INFLUENCES", comment: "Style DNA section eyebrow")
            )
            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                ForEach(influences, id: \.self) { influence in
                    StyleDNAInfluencePill(title: influence.displayName)
                }
            }
        }
    }

    private func silhouetteSection(_ silhouette: StyleDNASilhouette) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(
                title: String(localized: "How it should sit", comment: "Style DNA section title"),
                eyebrow: String(localized: "SILHOUETTE", comment: "Style DNA section eyebrow")
            )
            if !silhouette.headline.isEmpty {
                Text(silhouette.headline)
                    .astraText(.title2)
                    .foregroundStyle(AstraColor.textPrimary)
            }
            if !silhouette.detail.isEmpty {
                Text(silhouette.detail)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
            }
        }
    }

    private func signatureSection(_ items: [StyleDNARecommendation]) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "Pieces worth owning", comment: "Style DNA section title"),
                eyebrow: String(localized: "SIGNATURE", comment: "Style DNA section eyebrow")
            )
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(AstraColor.divider) }
                StyleDNASignatureRow(recommendation: item)
            }
        }
    }

    private func prioritySection(_ priorities: [StyleDNAPriority]) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "Start here", comment: "Style DNA section title"),
                eyebrow: String(localized: "IN ORDER", comment: "Style DNA section eyebrow")
            )
            ForEach(priorities) { priority in
                StyleDNAPriorityRow(priority: priority)
            }
        }
    }
}
