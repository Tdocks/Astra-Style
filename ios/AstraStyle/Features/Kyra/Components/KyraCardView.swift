//
//  KyraCardView.swift
//  AstraStyle
//
//  The structured card renderer (P5-KYRA-14): one view per hydrated card
//  kind, dispatched by exhaustive switch. No `default:` branch exists
//  because none can execute — an unknown wire card type is dropped by the
//  response decoder before hydration (KyraResponse.swift), so the five
//  kinds below plus the honest `.unavailable` degrade case are the entire
//  input space.
//
//  THE OUTFIT CARD IS THE CLOSET CAROUSEL'S COMPONENTS, NOT A PARALLEL
//  DRAWING. `LookSilhouetteView` + `LookGarment` + `AstraScoreMeter` are
//  the same pieces the Home hero card and Closet looks carousel already
//  use — P5-KYRA-14's acceptance criterion asks for exactly this reuse,
//  and it is also what keeps "an outfit" looking like one thing across
//  the app rather than three interpretations of one.
//

import SwiftUI

struct KyraCardView: View {
    let card: KyraRenderedCard
    let entryID: UUID
    var viewModel: KyraConversationViewModel

    var body: some View {
        switch card {
        case .outfit(let model):
            KyraOutfitCardView(model: model)
        case .closetItem(let model):
            KyraClosetItemCardView(model: model)
        case .product(let model):
            KyraProductCardView(model: model)
        case .comparisonTable(_, let table):
            KyraComparisonTableView(table: table)
        case .action(_, let action):
            // An action CARD renders as the same control as a suggested
            // action — one implementation of "a button Kyra offered", not
            // two — and passes through the same performability filter.
            if viewModel.canPerform(action, in: entryForFilter) {
                KyraActionButton(action: action, entryID: entryID, viewModel: viewModel)
            }
        case .unavailable(let model):
            KyraUnavailableCardView(model: model, entryID: entryID, viewModel: viewModel)
        }
    }

    /// `canPerform` reads the entry's cards to find an action's target;
    /// resolve it once here.
    private var entryForFilter: KyraTranscriptEntry {
        viewModel.entries.first { $0.id == entryID }
            ?? KyraTranscriptEntry(id: entryID, role: .assistant, text: "")
    }
}

// MARK: - Outfit

struct KyraOutfitCardView: View {
    let model: KyraOutfitCardModel

    var body: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(model.outfit.name)
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                LookSilhouetteView(garments: model.garments)
                if let score = model.outfit.compatibilityScore {
                    AstraScoreMeter(
                        score: score,
                        title: String(localized: "Compatibility", comment: "Outfit card score meter title"),
                        style: .compact
                    )
                }
                if let reason = model.outfit.description {
                    // The outfit row's stored description — the generator's
                    // "why" — not the turn-specific reason: the wire card
                    // carries one additively but the Swift card shape does
                    // not surface it yet (see the report in KyraResponse's
                    // header about additive fields).
                    Text(reason)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("kyra.card.outfit")
    }
}

// MARK: - Closet item

struct KyraClosetItemCardView: View {
    let model: KyraClosetItemCardModel

    var body: some View {
        AstraCard {
            HStack(spacing: AstraSpacing.sm) {
                AstraRemoteImage(
                    url: model.imageURL,
                    aspectRatio: 1,
                    thumbnail: .listRowThumbnail,
                    cornerRadius: AstraRadius.small,
                    contentMode: .fit,
                    accessibilityDescription: model.item.name
                )
                // Matches `.listRowThumbnail`'s 56 pt decode target.
                .frame(width: AstraSize.minTapTarget + AstraSpacing.sm)
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(model.item.name)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textPrimary)
                    if let brand = model.item.brand {
                        Text(brand)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
                    Text(model.item.category.displayName)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("kyra.card.closetItem")
    }
}

// MARK: - Product

/// Renders the user's own evaluation of the cited product — verdict,
/// reasoning, and the wardrobe numbers — because that is all the client
/// can fetch from a `product_candidate_id` today (no candidate
/// fetch-by-id exists; `KyraProductCardModel`'s header records the gap).
/// Cost-per-wear is deliberately omitted: the evaluation carries no
/// currency, and a bare number would read as a claim in the user's own
/// currency that nothing actually made.
struct KyraProductCardView: View {
    let model: KyraProductCardModel

    var body: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(String(localized: "Kyra's read on this product", comment: "Product card title"))
                    .astraText(.micro)
                    .foregroundStyle(AstraColor.textMuted)
                Text(verdictLabel)
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                AstraScoreMeter(
                    score: model.evaluation.compatibilityScore,
                    title: String(localized: "Wardrobe compatibility", comment: "Product card score meter title"),
                    style: .compact
                )
                Text(String(
                    localized: "Unlocks \(model.evaluation.outfitsUnlocked) new outfits with what you own.",
                    comment: "Product card outfits-unlocked line"
                ))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                Text(model.evaluation.reasoning)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("kyra.card.product")
    }

    private var verdictLabel: String {
        switch model.evaluation.verdict {
        case .buy: String(localized: "Buy it", comment: "Product verdict")
        case .consider: String(localized: "Worth considering", comment: "Product verdict")
        case .waitForSale: String(localized: "Wait for a sale", comment: "Product verdict")
        case .skip: String(localized: "Skip it", comment: "Product verdict")
        }
    }
}

// MARK: - Comparison table

struct KyraComparisonTableView: View {
    let table: ComparisonTable

    var body: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text(table.title)
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                Grid(alignment: .leading, horizontalSpacing: AstraSpacing.md, verticalSpacing: AstraSpacing.xs) {
                    GridRow {
                        // Keyed by offset, not by the string: two columns
                        // may legitimately share a header ("Price" twice in
                        // a two-product comparison).
                        ForEach(Array(table.columnHeaders.enumerated()), id: \.offset) { _, header in
                            Text(header)
                                .astraText(.micro)
                                .foregroundStyle(AstraColor.textMuted)
                        }
                    }
                    Divider().overlay(AstraColor.divider)
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            // Padded/truncated to the header count so a
                            // ragged model-authored row misaligns into
                            // honesty (an empty cell) rather than shifting
                            // every column after it.
                            ForEach(Array(normalized(row).enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .astraText(.caption)
                                    .foregroundStyle(AstraColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("kyra.card.comparisonTable")
    }

    private func normalized(_ row: [String]) -> [String] {
        let width = table.columnHeaders.count
        guard width > 0 else { return row }
        if row.count >= width { return Array(row.prefix(width)) }
        return row + Array(repeating: "", count: width - row.count)
    }
}

// MARK: - Unavailable

struct KyraUnavailableCardView: View {
    let model: KyraUnavailableCardModel
    let entryID: UUID
    var viewModel: KyraConversationViewModel

    var body: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                Text(model.summary)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.isRetryable && !viewModel.isOffline {
                    Button(String(localized: "Try loading it again", comment: "Retries hydrating a Kyra card")) {
                        Task { await viewModel.rehydrateCards(entryID: entryID) }
                    }
                    .buttonStyle(.astraTertiary)
                    .accessibilityIdentifier("kyra.card.retry")
                }
            }
        }
        .accessibilityIdentifier("kyra.card.unavailable")
    }
}

// MARK: - Action button

struct KyraActionButton: View {
    let action: KyraSuggestedAction
    let entryID: UUID
    var viewModel: KyraConversationViewModel

    var body: some View {
        Button {
            Task { await viewModel.perform(action, in: entryID) }
        } label: {
            HStack(spacing: AstraSpacing.xs) {
                if isInFlight {
                    ProgressView()
                        .tint(AstraColor.accentChampagneAccessible)
                } else if isPerformed {
                    Image(systemName: "checkmark")
                        .astraIcon(.emphasis)
                }
                Text(action.label)
            }
        }
        .buttonStyle(.astraSecondary)
        .disabled(isInFlight || isPerformed)
        .accessibilityIdentifier("kyra.action.\(action.id)")
    }

    private var isPerformed: Bool {
        viewModel.performedActionKeys.contains(viewModel.actionKey(action, entryID: entryID))
    }

    private var isInFlight: Bool {
        viewModel.inFlightActionKeys.contains(viewModel.actionKey(action, entryID: entryID))
    }
}
