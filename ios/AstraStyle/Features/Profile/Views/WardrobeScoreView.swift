//
//  WardrobeScoreView.swift
//  AstraStyle
//
//  Profile summary and detail for the live, server-computed Wardrobe Score.
//

import SwiftUI
import Observation

struct ProfileWardrobeScoreCard: View {
    @State private var viewModel: WardrobeScoreViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: WardrobeScoreViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(String(localized: "Your wardrobe", comment: "Profile Wardrobe Score section label"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
            Button {
                router.push(.wardrobeScoreDetail)
            } label: {
                cardContents
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.wardrobeScoreRow")
            .accessibilityHint(Text(String(
                localized: "Opens the Wardrobe Score breakdown",
                comment: "Profile Wardrobe Score summary hint"
            )))
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var cardContents: some View {
        AstraCard {
            switch viewModel.phase {
            case .loading:
                HStack(spacing: AstraSpacing.sm) {
                    ProgressView().tint(AstraColor.accentChampagneAccessible)
                    Text(String(localized: "Reading your wardrobe.", comment: "Wardrobe Score loading state"))
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
            case .ready(let snapshot):
                if let score = snapshot.score {
                    HStack(spacing: AstraSpacing.md) {
                        AstraScoreMeter(
                            score: score.overall,
                            title: String(localized: "Wardrobe Score", comment: "Wardrobe Score title"),
                            style: .compact
                        )
                        Spacer(minLength: AstraSpacing.sm)
                        Image(systemName: "chevron.right")
                            .astraIcon(.disclosure)
                            .foregroundStyle(AstraColor.textMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
                    if let count = snapshot.activeItemCount {
                        Text(String(localized: "Based on \(count) active pieces", comment: "Wardrobe Score item count"))
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
                } else {
                    HStack(spacing: AstraSpacing.md) {
                        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                            Text(String(localized: "Wardrobe Score", comment: "Wardrobe Score title"))
                                .astraText(.headline)
                                .foregroundStyle(AstraColor.textPrimary)
                            Text(String(localized: "Add a piece to start seeing how your closet works together.", comment: "Empty Wardrobe Score prompt"))
                                .astraText(.caption)
                                .foregroundStyle(AstraColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: AstraSpacing.sm)
                        Image(systemName: "chevron.right")
                            .astraIcon(.disclosure)
                            .foregroundStyle(AstraColor.textMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
                }
            case .failed:
                HStack(spacing: AstraSpacing.md) {
                    VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                        Text(String(localized: "Wardrobe Score", comment: "Wardrobe Score title"))
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.textPrimary)
                        Text(String(localized: "Tap to try loading it again.", comment: "Wardrobe Score retry hint"))
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
                    Spacer(minLength: AstraSpacing.sm)
                    Image(systemName: "arrow.clockwise")
                        .astraIcon(.disclosure)
                        .foregroundStyle(AstraColor.textMuted)
                }
                .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }
}

struct WardrobeScoreDetailView: View {
    @State private var viewModel: WardrobeScoreViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: WardrobeScoreViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                switch viewModel.phase {
                case .loading:
                    loadingState
                case .ready(let snapshot):
                    if let score = snapshot.score {
                        scoreContent(score, snapshot: snapshot)
                    } else {
                        emptyState
                    }
                case .failed(let message):
                    failureState(message)
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Wardrobe Score", comment: "Wardrobe Score detail title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.retry() }
    }

    private var loadingState: some View {
        HStack(spacing: AstraSpacing.sm) {
            ProgressView().tint(AstraColor.accentChampagneAccessible)
            Text(String(localized: "Reading your wardrobe.", comment: "Wardrobe Score loading state"))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("profile.wardrobeScore.loading")
    }

    private var emptyState: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                Image(systemName: "square.grid.2x2")
                    .astraIcon(.feature)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                    .accessibilityHidden(true)
                Text(String(localized: "Start with your closet", comment: "Empty Wardrobe Score title"))
                    .astraText(.title2)
                    .foregroundStyle(AstraColor.textPrimary)
                Text(String(localized: "Add a few pieces and Astra can show how versatile, balanced, and well-used your wardrobe is.", comment: "Empty Wardrobe Score explanation"))
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textSecondary)
                Button(String(localized: "Scan a piece", comment: "Opens closet scanner from empty Wardrobe Score")) {
                    router.selectedTab = .closet
                    router.startScan()
                }
                .buttonStyle(.astraPrimary)
                .accessibilityIdentifier("profile.wardrobeScore.scanFirstPiece")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func scoreContent(_ score: WardrobeScore, snapshot: WardrobeScoreSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xl) {
            AstraCard {
                VStack(spacing: AstraSpacing.md) {
                    AstraScoreMeter(
                        score: score.overall,
                        title: String(localized: "Your wardrobe", comment: "Wardrobe Score meter title"),
                        style: .hero
                    )
                    if let count = snapshot.activeItemCount {
                        Text(String(localized: "\(count) active pieces", comment: "Wardrobe Score active item count"))
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
                    Text(String(localized: "A snapshot of how your pieces work together and how often they earn a place in your rotation.", comment: "Wardrobe Score explanation"))
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                Text(String(localized: "What shapes your score", comment: "Wardrobe Score components heading"))
                    .astraText(.title2)
                    .foregroundStyle(AstraColor.textPrimary)
                ForEach(WardrobeScoreComponentName.allCases) { component in
                    componentRow(component, score: score, isDegraded: snapshot.degradedComponents.contains(component))
                }
            }

            if !snapshot.degradedComponents.isEmpty {
                Text(String(localized: "Some parts are still learning from your closet details and wear history. Your score will become more complete as you use Astra.", comment: "Wardrobe Score data completeness note"))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.wardrobeScore.learningNote")
            }
            if let confidence = snapshot.confidence, confidence < 1 {
                Text(String(localized: "Your score can shift as your active closet grows and Astra gets a fuller picture.", comment: "Wardrobe Score sparse closet note"))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func componentRow(
        _ component: WardrobeScoreComponentName,
        score: WardrobeScore,
        isDegraded: Bool
    ) -> some View {
        let value = componentValue(component, score: score)
        return AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                HStack(spacing: AstraSpacing.sm) {
                    Text(component.title)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textPrimary)
                    if isDegraded {
                        Text(String(localized: "Building", comment: "Wardrobe Score component has limited data"))
                            .astraText(.micro)
                            .foregroundStyle(AstraColor.textMuted)
                    }
                    Spacer(minLength: AstraSpacing.sm)
                    Text("\(value)")
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textPrimary)
                        .monospacedDigit()
                        .accessibilityLabel(Text(String(localized: "\(component.title), \(value) out of 100", comment: "Wardrobe Score component value")))
                }
                ProgressView(value: Double(value), total: 100)
                    .tint(AstraColor.accentChampagneAccessible)
                    .accessibilityHidden(true)
            }
        }
    }

    private func componentValue(_ component: WardrobeScoreComponentName, score: WardrobeScore) -> Int {
        switch component {
        case .versatility: score.versatility
        case .fitConfidence: score.fitConfidence
        case .occasionCoverage: score.occasionCoverage
        case .colorCohesion: score.colorCohesion
        case .wearUtilization: score.wearUtilization
        case .condition: score.condition
        case .redundancyControl: score.redundancyControl
        }
    }

    private func failureState(_ message: String) -> some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                Text(String(localized: "Your score didn't load", comment: "Wardrobe Score error title"))
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.warningAmber)
                Text(message)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                Button(String(localized: "Try again", comment: "Retry Wardrobe Score load")) {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.astraSecondary)
                .accessibilityIdentifier("profile.wardrobeScore.retry")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
@Observable
final class WardrobeScoreViewModel {
    enum Phase: Sendable {
        case loading
        case ready(WardrobeScoreSnapshot)
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private let closetRepository: ClosetRepository

    init(closetRepository: ClosetRepository) {
        self.closetRepository = closetRepository
    }

    func load() async {
        await fetch()
    }

    func retry() async {
        phase = .loading
        await fetch()
    }

    private func fetch() async {
        do {
            phase = .ready(try await closetRepository.fetchWardrobeScoreSnapshot())
        } catch let error as AstraError {
            phase = .failed(error.message)
        } catch {
            phase = .failed(String(localized: "Check your connection and try again.", comment: "Wardrobe Score load error"))
        }
    }
}
