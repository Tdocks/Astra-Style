//
//  ProductDecisionView.swift
//  AstraStyle
//
//  Spec §6.19 as a door, not a store. Verdict, unlocks, reasoning, the
//  scores evaluate already returns. No alternatives grid, no wishlist,
//  no "Kyra says" frame on scorer copy.
//

import SwiftUI

struct ProductDecisionView: View {
    @State private var viewModel: ProductDecisionViewModel
    @State private var isShowingSource = false

    init(viewModel: ProductDecisionViewModel) {
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
            case .loaded(let loaded):
                loadedContent(loaded)
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Should you buy this?", comment: "Product decision page title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .sheet(isPresented: $isShowingSource) {
            if let url = viewModel.sourceURL {
                ProductSourceSafariView(url: url)
            }
        }
    }

    private func loadedContent(_ loaded: ProductDecisionViewModel.Loaded) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                identity(loaded.candidate)
                scores(loaded.evaluation)
                if viewModel.canOpenSourceURL {
                    AstraButton(
                        title: String(localized: "Open the page you pasted", comment: "Reopens the source URL after buy/consider")
                    ) {
                        isShowingSource = true
                    }
                    .accessibilityIdentifier("productDecision.openSource")
                }
                if let shareText = viewModel.shareText {
                    ShareLink(item: shareText) {
                        Label(
                            String(localized: "Share this verdict", comment: "Share skip/wait, never a buy CTA"),
                            systemImage: "square.and.arrow.up"
                        )
                        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                    }
                    .buttonStyle(.astraSecondary)
                    .accessibilityIdentifier("productDecision.share")
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func identity(_ candidate: ProductCandidate?) -> some View {
        if let candidate {
            Text(candidate.name)
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(candidate.retailer)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
        }
    }

    @ViewBuilder
    private func scores(_ evaluation: ProductEvaluation) -> some View {
        Text(verdictLabel(evaluation.verdict))
            .astraText(.displayL)
            .foregroundStyle(AstraColor.textPrimary)
            .accessibilityIdentifier("productDecision.verdict")
        Text(unlockLine(evaluation.outfitsUnlocked))
            .astraText(.callout)
            .foregroundStyle(AstraColor.textSecondary)
            .accessibilityIdentifier("productDecision.unlocks")
        Text(evaluation.reasoning)
            .astraText(.body)
            .foregroundStyle(AstraColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("productDecision.reasoning")
        AstraScoreMeter(
            score: evaluation.compatibilityScore,
            title: String(localized: "Works with what you own", comment: "Decision page compatibility"),
            style: .compact
        )
        AstraScoreMeter(
            score: evaluation.redundancyScore,
            title: String(localized: "How close it is to something you already own", comment: "Decision page redundancy"),
            style: .compact
        )
        if let cost = evaluation.expectedCostPerWear {
            Text(costPerWearLine(cost))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
        }
    }

    private func failed(_ error: AstraError) -> some View {
        VStack(spacing: AstraSpacing.md) {
            Text(error.message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
            if error.isRetryable {
                Button(String(localized: "Try Again", comment: "Retries product evaluation")) {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.astraSecondary)
            }
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func verdictLabel(_ verdict: KyraVerdict) -> String {
        switch verdict {
        case .buy: String(localized: "Buy it", comment: "Product verdict")
        case .consider: String(localized: "Worth considering", comment: "Product verdict")
        case .waitForSale: String(localized: "Wait for a sale", comment: "Product verdict")
        case .skip: String(localized: "Skip it", comment: "Product verdict")
        }
    }

    private func unlockLine(_ count: Int) -> String {
        if count == 0 {
            return String(
                localized: "It does not unlock a new outfit with what you own.",
                comment: "Decision page when unlock count is zero"
            )
        }
        return String(
            localized: "Unlocks \(count) new outfits with what you own.",
            comment: "Decision page outfits-unlocked line"
        )
    }

    private func costPerWearLine(_ cost: Decimal) -> String {
        String(
            localized: "About \(cost) a wear, if you wear it like the rest of this category.",
            comment: "Decision page cost per wear"
        )
    }
}
