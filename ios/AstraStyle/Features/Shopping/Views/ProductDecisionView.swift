//
//  ProductDecisionView.swift
//  AstraStyle
//
//  Spec §6.19 as a door, not a store. Verdict, unlocks, reasoning, save
//  and purchased. No alternatives grid, no "Kyra says" frame on scorer copy.
//

import SwiftUI

struct ProductDecisionView: View {
    @State private var viewModel: ProductDecisionViewModel
    @State private var isShowingSource = false
    @Environment(AppRouter.self) private var router

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
        .navigationTitle(viewModel.isShowingHistoricalSnapshot
            ? String(localized: "Past decision", comment: "Historical product decision title")
            : String(localized: "Should you buy this?", comment: "Product decision page title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .onChange(of: viewModel.pendingPaywall) { _, context in
            if let context {
                router.presentModal(.paywall(context: context))
                viewModel.clearPendingPaywall()
            }
        }
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
                evaluationFreshnessNotice(loaded)
                scores(loaded.evaluation)
                if loaded.isCachedSnapshot {
                    Button {
                        Task { await viewModel.refreshEvaluation() }
                    } label: {
                        Text(String(localized: "Refresh evaluation", comment: "Explicitly requests a fresh product evaluation"))
                            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                    }
                    .buttonStyle(.astraPrimary)
                    .accessibilityIdentifier("productDecision.refreshEvaluation")
                }
                if viewModel.canOpenSourceURL {
                    AstraButton(
                        title: String(localized: "Open the page you pasted", comment: "Reopens the source URL after buy/consider")
                    ) {
                        isShowingSource = true
                    }
                    .accessibilityIdentifier("productDecision.openSource")
                }
                saveActions
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
    private var saveActions: some View {
        if case .loaded(let loaded) = viewModel.state, loaded.isCachedSnapshot {
            Text(String(
                localized: "Reconnect to refresh this decision or change saved items.",
                comment: "Offline cached product decision cannot update wishlist or purchase state"
            ))
            .astraText(.caption)
            .foregroundStyle(AstraColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("productDecision.offlineActions")
        } else if viewModel.isPurchased {
            Text(String(localized: "Marked as purchased.", comment: "Product decision purchased state"))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .accessibilityIdentifier("productDecision.purchased")
        } else {
            Button {
                Task { await viewModel.toggleWishlist() }
            } label: {
                Text(
                    viewModel.isOnWishlist
                        ? String(localized: "Saved", comment: "Remove from wishlist")
                        : String(localized: "Save for later", comment: "Add to wishlist")
                )
                .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("productDecision.wishlist")
            Button {
                Task { await viewModel.markPurchased() }
            } label: {
                Text(String(localized: "I bought this", comment: "Mark product purchased"))
                    .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("productDecision.markPurchased")
        }
        if let wishlistMessage = viewModel.wishlistMessage {
            Text(wishlistMessage)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
        }
    }

    @ViewBuilder
    private func identity(_ candidate: ProductCandidate?) -> some View {
        if let candidate {
            if candidate.imageURL != nil {
                AstraRemoteImage(
                    url: candidate.imageURL,
                    aspectRatio: 4.0 / 5.0,
                    accessibilityDescription: candidate.retailerLabel.map { "\(candidate.name) by \($0)" } ?? candidate.name
                )
            }
            Text(candidate.name)
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let retailerLabel = candidate.retailerLabel {
                Text(retailerLabel)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
            }
            if candidate.isSponsored || candidate.isAffiliateLink {
                Text(String(
                    localized: "Commercial link. Astra may earn a commission if you buy; the verdict is still based on your wardrobe.",
                    comment: "In-flow affiliate disclosure on a product decision"
                ))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
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
            if viewModel.isHistoricalEntry {
                Button(String(localized: "Evaluate now", comment: "Explicitly scores a product when a saved history snapshot is unavailable")) {
                    Task { await viewModel.refreshEvaluation() }
                }
                .buttonStyle(.astraSecondary)
                .accessibilityIdentifier("productDecision.evaluateHistoricalItem")
            } else if error.isRetryable {
                Button(String(localized: "Try Again", comment: "Retries product evaluation")) {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.astraSecondary)
            }
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func evaluationFreshnessNotice(_ loaded: ProductDecisionViewModel.Loaded) -> some View {
        let date = loaded.evaluation.createdAt.formatted(date: .abbreviated, time: .shortened)
        let message = loaded.isCachedSnapshot
            ? String(localized: "Last evaluated \(date). This is a saved result from then, not a current recommendation.", comment: "Disclosure that a product verdict is a historical snapshot")
            : String(localized: "Evaluated \(date) against your wardrobe.", comment: "Timestamp for a fresh server product evaluation")
        return Text(message)
        .astraText(.caption)
        .foregroundStyle(AstraColor.textMuted)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier(loaded.isCachedSnapshot ? "productDecision.cachedSnapshot" : "productDecision.freshness")
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
        let formattedCost = cost.formatted(.number.precision(.fractionLength(0...2)))
        return String(
            localized: "About \(formattedCost) a wear, if you wear it like the rest of this category.",
            comment: "Decision page cost per wear"
        )
    }
}
