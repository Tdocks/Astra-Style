import SwiftUI

struct ClosetItemInsightsSection: View {
    let viewModel: ClosetItemDetailViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text("Closet insights").astraText(.title2).accessibilityIdentifier("closet.item.insights.title")
            if viewModel.isLoadingInsights {
                ProgressView("Loading insights…")
            }
            if let error = viewModel.insightsError {
                Text(error).astraText(.callout)
                Button("Retry insights") { Task { await viewModel.loadInsights() } }
                    .buttonStyle(.astraSecondary)
            }
            if let insights = viewModel.insights {
                Text("Similarity to your closet: \(insights.redundancyScore)/100").astraText(.headline)
                Text("Higher means this piece is more similar to another active item in the same category and season. Similarity doesn't mean you should remove it.")
                    .astraText(.caption)
                if !insights.missingRedundancyInputs.isEmpty {
                    Text("Some details are missing: \(insights.missingRedundancyInputs.joined(separator: ", ")). Edit the piece to improve this estimate.")
                        .astraText(.caption)
                }
                ForEach(insights.similarItems, id: \.itemId) { similar in
                    if let item = viewModel.insightItems[similar.itemId] {
                        pieceButton(item, detail: "\(similar.similarity)/100 similarity")
                    }
                }
                Text("Best pairings").astraText(.headline).accessibilityIdentifier("closet.item.insights.pairings")
                Text("Ranked using outfit compatibility, comparing two pieces. These are starting points for a look; today's weather and calendar aren't included here.")
                    .astraText(.caption)
                if insights.pairings.isEmpty {
                    Text("No available complementary pieces found. Check laundry status or add more pieces.").astraText(.body)
                }
                ForEach(insights.pairings, id: \.itemId) { pairing in
                    if let item = viewModel.insightItems[pairing.itemId] {
                        pieceButton(item, detail: "\(pairing.score)/100 pairing score")
                    }
                }
                Text("Saved looks with this piece").astraText(.headline)
                if insights.savedOutfitIds.isEmpty {
                    Text("No saved looks include this piece yet.").astraText(.body)
                }
                ForEach(Array(insights.savedOutfitIds.enumerated()), id: \.element) { index, id in
                    Button("Open saved look \(index + 1)") { router.push(ClosetRoute.outfitDetail(outfitID: id)) }
                        .buttonStyle(.astraSecondary)
                }
                if let reason = insights.replacementReason {
                    Text("Care or replacement").astraText(.headline)
                    Text(reason == "recorded_damage"
                         ? "You marked this piece as damaged. Consider repair before replacing it."
                         : "You marked this piece as worn. Check its condition and consider repair or replacement when needed.")
                        .astraText(.body)
                }
            }
        }

    }

    private func pieceButton(_ item: ClosetItem, detail: String) -> some View {
        Button {
            router.push(ClosetRoute.itemDetail(itemID: item.id))
        } label: {
            VStack(alignment: .leading) {
                Text(item.name).astraText(.headline)
                Text(detail).astraText(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.astraSecondary)
    }
}
