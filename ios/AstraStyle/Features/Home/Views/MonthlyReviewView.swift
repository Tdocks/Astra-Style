import SwiftUI

struct MonthlyReviewView: View {
    @State private var viewModel: MonthlyReviewViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: MonthlyReviewViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            Group {
                switch viewModel.state {
                case .loading:
                    ProgressView().tint(AstraColor.accentChampagne).padding(.top, AstraSpacing.xl)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Review unavailable", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { Task { await viewModel.load() } }
                            .buttonStyle(.astraSecondary)
                    }
                case .loaded(let snapshot):
                    review(snapshot)
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationTitle("Monthly Review")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private func review(_ snapshot: MonthlyReviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(snapshot.monthTitle).astraText(.displayL).foregroundStyle(AstraColor.textPrimary)
                Text("A clear look at what you wore and what worked.")
                    .astraText(.callout).foregroundStyle(AstraColor.textSecondary)
            }
            stats(snapshot)
            section("Best purchase", value: snapshot.bestPurchase ?? "No purchase evaluations this month.", detail: snapshot.bestPurchaseOutfitsUnlocked.map { "Opens \($0) new outfit combinations." })
            section("Underused pieces", value: snapshot.underusedItems.isEmpty ? "Nothing stands out as underused yet." : snapshot.underusedItems.joined(separator: " · "))
            section(
                "Wardrobe versatility",
                value: snapshot.versatilitySummary,
                identifier: "monthlyReview.versatility"
            )
            kyraReview
        }
    }

    @ViewBuilder
    private var kyraReview: some View {
        switch viewModel.authoredReviewState {
        case .ready:
            Button {
                Task { await viewModel.generateAuthoredReview() }
            } label: {
                Label("Ask Kyra to write this review", systemImage: "text.quote")
                    .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("monthlyReview.generateKyraReview")
        case .generating(let previous):
            HStack(spacing: AstraSpacing.sm) {
                ProgressView().tint(AstraColor.accentChampagne)
                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    if let previous {
                        Text("Kyra's review").astraText(.headline).foregroundStyle(AstraColor.textPrimary)
                        Text(previous.message).astraText(.body).foregroundStyle(AstraColor.textSecondary)
                        Text("Refreshing with this month's recorded facts…").astraText(.caption).foregroundStyle(AstraColor.textMuted)
                    } else {
                        Text("Kyra is preparing your review…")
                            .astraText(.body).foregroundStyle(AstraColor.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AstraSpacing.md)
            .accessibilityIdentifier("monthlyReview.kyraLoading")
        case .generated(let authored):
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                section(
                    "Kyra's review",
                    value: authored.message,
                    detail: authored.cacheSaved ? "Saved for this month's recorded facts." : "This review is available now, but could not be saved for next time.",
                    identifier: "monthlyReview.kyraSummary"
                )
                if authored.cacheSaved {
                    Button {
                        Task { await viewModel.refreshAuthoredReview() }
                    } label: {
                        Label("Refresh with Kyra", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                    }
                    .buttonStyle(.astraSecondary)
                    .accessibilityIdentifier("monthlyReview.refreshKyraReview")
                } else {
                    Button {
                        Task { await viewModel.saveGeneratedReview() }
                    } label: {
                        Label("Save review for next time", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                    }
                    .buttonStyle(.astraSecondary)
                    .accessibilityIdentifier("monthlyReview.saveKyraReview")
                }
                Button {
                    router.startAskKyra(threadID: authored.threadID)
                } label: {
                    Label("Continue with Kyra", systemImage: "bubble.left")
                        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                }
                .buttonStyle(.astraSecondary)
                .accessibilityIdentifier("monthlyReview.continueWithKyra")
            }
        case .failed(let message, _, let rateLimited):
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(message).astraText(.body).foregroundStyle(AstraColor.textSecondary)
                if rateLimited {
                    Button("See Premium plans") {
                        router.presentModal(.paywall(context: .kyraDailyLimit))
                    }
                    .buttonStyle(.astraSecondary)
                    .accessibilityIdentifier("monthlyReview.kyraPaywall")
                } else {
                    Button("Try Kyra again") {
                        Task { await viewModel.generateAuthoredReview() }
                    }
                    .buttonStyle(.astraSecondary)
                    .accessibilityIdentifier("monthlyReview.retryKyraReview")
                }
            }
            .accessibilityIdentifier("monthlyReview.kyraFailure")
        case .refreshFailed(let message, let previous, let rateLimited):
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                section("Kyra's review", value: previous.message, detail: "Saved review · refresh did not complete.", identifier: "monthlyReview.kyraSummary")
                Text(message).astraText(.body).foregroundStyle(AstraColor.textSecondary)
                if rateLimited {
                    Button("See Premium plans") { router.presentModal(.paywall(context: .kyraDailyLimit)) }
                        .buttonStyle(.astraSecondary)
                        .accessibilityIdentifier("monthlyReview.kyraPaywall")
                } else {
                    Button("Try refresh again") { Task { await viewModel.refreshAuthoredReview() } }
                        .buttonStyle(.astraSecondary)
                        .accessibilityIdentifier("monthlyReview.retryKyraReview")
                }
                Button {
                    router.startAskKyra(threadID: previous.threadID)
                } label: {
                    Label("Continue with Kyra", systemImage: "bubble.left")
                        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                }
                .buttonStyle(.astraSecondary)
                .accessibilityIdentifier("monthlyReview.continueWithKyra")
            }
            .accessibilityIdentifier("monthlyReview.kyraRefreshFailure")
        case .cacheUnavailable(let message):
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(message).astraText(.body).foregroundStyle(AstraColor.textSecondary)
                Button("Check saved review again") { Task { await viewModel.load() } }
                    .buttonStyle(.astraSecondary)
                    .accessibilityIdentifier("monthlyReview.retrySavedReview")
            }
            .accessibilityIdentifier("monthlyReview.savedReviewUnavailable")
        }
    }

    private func stats(_ snapshot: MonthlyReviewSnapshot) -> some View {
        VStack(spacing: AstraSpacing.sm) {
            HStack(spacing: AstraSpacing.sm) {
                stat("New pieces", value: "\(snapshot.newItemCount)", icon: "plus.square")
                stat("Looks worn", value: "\(snapshot.wearCount)", icon: "checkmark.circle")
            }
            HStack(spacing: AstraSpacing.sm) {
                stat("Outfit variety", value: "\(snapshot.uniqueOutfitCount)", icon: "square.stack")
                stat("Tracked spend", value: snapshot.trackedSpend.isEmpty ? "—" : snapshot.trackedSpend.joined(separator: " · "), icon: "creditcard")
            }
        }
    }

    private func stat(_ title: String, value: String, icon: String) -> some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                Image(systemName: icon).foregroundStyle(AstraColor.accentChampagneAccessible)
                Text(value).astraText(.headline).foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("monthlyReview.statValue.\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
                Text(title).astraText(.caption).foregroundStyle(AstraColor.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section(
        _ title: String,
        value: String,
        detail: String? = nil,
        identifier: String? = nil
    ) -> some View {
        let card = AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                Text(title).astraText(.headline).foregroundStyle(AstraColor.textPrimary)
                Text(value).astraText(.body).foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).astraText(.caption).foregroundStyle(AstraColor.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let identifier {
            card.accessibilityIdentifier(identifier)
        } else {
            card
        }
    }
}
