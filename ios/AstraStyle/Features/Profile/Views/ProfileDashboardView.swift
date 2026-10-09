//
//  ProfileDashboardView.swift
//  AstraStyle
//
//  Everyday wardrobe totals and the recent Style Journey entry point.
//

import SwiftUI

struct ProfileDashboardCard: View {
    @State private var viewModel: ProfileDashboardViewModel
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(viewModel: ProfileDashboardViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: AstraSpacing.md),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(String(localized: "Your closet at a glance", comment: "Profile dashboard section title"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("profile.dashboard.title")
            AstraCard {
                switch viewModel.phase {
                case .loading:
                    loadingState
                case .ready(let data):
                    dashboard(data)
                case .failed(let message):
                    failureState(message)
                }
            }
        }
        .task { await viewModel.load() }
    }

    private var loadingState: some View {
        HStack(spacing: AstraSpacing.sm) {
            ProgressView().tint(AstraColor.accentChampagne)
            Text(String(localized: "Gathering your closet stats.", comment: "Profile dashboard loading"))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
        .accessibilityIdentifier("profile.dashboard.loading")
    }

    private func dashboard(_ data: ProfileDashboardData) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: AstraSpacing.md) {
                metricCell(
                    title: String(localized: "Pieces", comment: "Profile stat label"),
                    value: String(data.closetMetrics.totalItems),
                    detail: String(localized: "in your closet", comment: "Profile stat detail")
                )
                metricCell(
                    title: String(localized: "Outfits", comment: "Profile stat label"),
                    value: String(data.outfitCount),
                    detail: String(localized: "saved looks", comment: "Profile stat detail")
                )
                metricCell(
                    title: String(localized: "Cost per wear", comment: "Profile stat label"),
                    value: costPerWearText(data.closetMetrics.averageCostPerWear),
                    detail: String(localized: "priced pieces", comment: "Profile stat detail")
                )
                metricCell(
                    title: String(localized: "This month", comment: "Profile stat label"),
                    value: spendText(data.monthlySpend),
                    detail: String(localized: "recorded spend", comment: "Profile stat detail")
                )
            }

            wornColorsSection(data)
            styleJourneyButton
        }
    }

    @ViewBuilder
    private func wornColorsSection(_ data: ProfileDashboardData) -> some View {
        if data.wornColors.isEmpty {
            Text(String(localized: "Your most-worn colors will appear after you log a few wears.", comment: "Profile most worn colors empty state"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(String(localized: "Most worn colors", comment: "Profile most worn colors heading"))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .accessibilityAddTraits(.isHeader)
                Text(data.wornColors.map { color in
                    let count = color.wears == 1
                        ? String(localized: "1 wear", comment: "Singular garment wear count")
                        : String(localized: "\(color.wears) wears", comment: "Plural garment wear count")
                    return String(localized: "\(color.color.capitalized) · \(count)", comment: "Most worn color and wear count")
                }.joined(separator: "   "))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var styleJourneyButton: some View {
        Button {
            router.push(ProfileRoute.styleJourney)
        } label: {
            HStack {
                Text(String(localized: "View your Style Journey", comment: "Opens Style Journey timeline"))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                Spacer(minLength: AstraSpacing.sm)
                Image(systemName: "chevron.right")
                    .astraIcon(.disclosure)
                    .foregroundStyle(AstraColor.textMuted)
            }
            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.dashboard.styleJourney")
    }

    private func metricCell(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(title)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
            Text(value)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text("\(title): \(value)"))
            Text(detail)
                .astraText(.micro)
                .foregroundStyle(AstraColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func costPerWearText(_ value: ClosetMetrics.AverageCostPerWear) -> String {
        switch value {
        case .amount(let amount, let currencyCode):
            CurrencyFormatting.formattedCostPerWear(amount, currencyCode: currencyCode)
        case .noPricesOnFile:
            String(localized: "Add prices", comment: "Profile cost-per-wear empty state")
        case .notYetWorn:
            String(localized: "Not worn yet", comment: "Profile cost-per-wear empty state")
        case .mixedCurrencies:
            String(localized: "Mixed currencies", comment: "Profile cost-per-wear mixed currency state")
        }
    }

    private func spendText(_ spend: [ProfileMonthlySpend]) -> String {
        guard !spend.isEmpty else {
            return String(localized: "No purchases", comment: "Profile current month spend empty state")
        }
        let lines = spend.prefix(2).map {
            CurrencyFormatting.formatted($0.amount, code: $0.currencyCode)
        }
        return lines.joined(separator: "\n")
    }

    private func failureState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text(message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
            Button(String(localized: "Try again", comment: "Retry Profile dashboard load")) {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.astraSecondary)
            .accessibilityIdentifier("profile.dashboard.retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StyleJourneyView: View {
    @State private var viewModel: ProfileDashboardViewModel

    init(viewModel: ProfileDashboardViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                switch viewModel.phase {
                case .loading:
                    ProgressView()
                        .tint(AstraColor.accentChampagne)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .ready(let data):
                    if data.journey.isEmpty {
                        AstraCard {
                            Text(String(localized: "Your journey starts with a closet piece or saved outfit. As you add, wear, and build looks, they will appear here.", comment: "Empty Style Journey"))
                                .astraText(.body)
                                .foregroundStyle(AstraColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ForEach(data.journey) { event in
                            journeyEvent(event)
                        }
                    }
                case .failed(let message):
                    AstraCard {
                        VStack(alignment: .leading, spacing: AstraSpacing.md) {
                            Text(message)
                                .astraText(.callout)
                                .foregroundStyle(AstraColor.textSecondary)
                            Button(String(localized: "Try again", comment: "Retry Style Journey load")) {
                                Task { await viewModel.retry() }
                            }
                            .buttonStyle(.astraSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Style Journey", comment: "Style Journey screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.retry() }
    }

    private func journeyEvent(_ event: ProfileJourneyEvent) -> some View {
        AstraCard {
            HStack(alignment: .top, spacing: AstraSpacing.md) {
                Image(systemName: symbol(for: event.kind))
                    .astraIcon(.control)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                    .frame(width: AstraSize.minTapTarget)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(event.title)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textPrimary)
                    Text(event.subtitle)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                    Text(event.date.formatted(date: .abbreviated, time: .omitted))
                        .astraText(.micro)
                        .foregroundStyle(AstraColor.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(for kind: ProfileJourneyEvent.Kind) -> String {
        switch kind {
        case .itemAdded: "plus"
        case .itemWorn: "checkmark.circle"
        case .outfitSaved: "hanger"
        }
    }
}
