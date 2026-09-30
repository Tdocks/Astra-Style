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
            section("Next priority", value: snapshot.nextPriority)
            section("Your challenge", value: snapshot.challenge)
            Button {
                router.startAskKyra(initialPrompt: snapshot.kyraPrompt, autoSend: true)
            } label: {
                Label("Talk this through with Kyra", systemImage: "bubble.left")
                    .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("monthlyReview.askKyra")
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
