//
//  DiscoverView.swift
//  AstraStyle
//
//  Editorial guides, two lookbook rails, and Unlocks. Home stays private.
//

import SwiftUI

struct DiscoverView: View {
    @State private var viewModel: DiscoverViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: DiscoverViewModel) {
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
            case .empty:
                empty
            case .loaded(let catalog):
                rails(catalog)
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Discover", comment: "Discover tab title"))
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.refresh() }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text(String(
                localized: "Wear This, then make a look public.",
                comment: "Discover empty — public lookbooks start from a worn morning"
            ))
            .astraText(.body)
            .foregroundStyle(AstraColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("discover.empty")
            Text(String(
                localized: "Paste a link on Home when something tempts you.",
                comment: "Discover empty unlocks hint"
            ))
            .astraText(.callout)
            .foregroundStyle(AstraColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rails(_ catalog: DiscoverViewModel.Catalog) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AstraSpacing.xl) {
                lookbookRail(
                    title: String(localized: "Your lookbooks", comment: "Discover own looks rail"),
                    looks: catalog.mine,
                    empty: String(
                        localized: "Wear This or save a look first.",
                        comment: "Discover own lookbooks empty"
                    ),
                    identifier: "discover.mine"
                )
                lookbookRail(
                    title: wornByOthersTitle,
                    looks: catalog.wornByOthers,
                    empty: String(
                        localized: "Wear This, then make a look public.",
                        comment: "Discover public looks empty"
                    ),
                    identifier: "discover.public"
                )
                unlocksRail(catalog.unlocks)
                DiscoverEditorialRail(
                    title: String(localized: "Style notes", comment: "Discover editorial education rail"),
                    guides: catalog.styleEducation,
                    identifier: "discover.editorial.style",
                    onSelect: openGuide
                )
                DiscoverEditorialRail(
                    title: String(localized: "In season", comment: "Discover seasonal guide rail"),
                    guides: catalog.seasonalGuides,
                    identifier: "discover.editorial.seasonal",
                    onSelect: openGuide
                )
                DiscoverEditorialRail(
                    title: String(localized: "Fit guides", comment: "Discover garment fit guide rail"),
                    guides: catalog.fitGuides,
                    identifier: "discover.editorial.fit",
                    onSelect: openGuide
                )
                DiscoverEditorialRail(
                    title: String(localized: "Brand field notes", comment: "Discover editorial brand rail"),
                    guides: catalog.brandSpotlights,
                    identifier: "discover.editorial.brand",
                    onSelect: openGuide
                )
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
    }

    private func openGuide(_ guide: DiscoverGuide) {
        switch guide.kind {
        case .fitGuide:
            router.push(DiscoverRoute.fitGuide(slug: guide.id))
        case .styleEducation, .seasonalGuide:
            router.push(DiscoverRoute.styleGuide(slug: guide.id))
        case .brandSpotlight:
            router.push(DiscoverRoute.brandSpotlight(brand: guide.id))
        }
    }

    /// Graph-keyed peer copy (ADR 0019). No Settings gender toggle.
    private var wornByOthersTitle: String {
        switch viewModel.wardrobeGraph {
        case .menswear3Role:
            String(localized: "Worn by other men", comment: "Discover public worn looks, men's graph")
        case .womenswear:
            String(localized: "Worn by other women", comment: "Discover public worn looks, women's graph")
        }
    }

    private func lookbookRail(
        title: String,
        looks: [DiscoverViewModel.DiscoverLook],
        empty: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
            if looks.isEmpty {
                Text(empty)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier).empty")
            } else {
                ForEach(looks) { look in
                    Button {
                        if look.isPublicLook {
                            router.push(DiscoverRoute.publicLook(id: look.id))
                        } else {
                            router.push(DiscoverRoute.lookbook(id: look.id))
                        }
                    } label: {
                        lookbookCard(look)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(identifier).\(look.id.uuidString)")
                }
            }
        }
    }

    private func lookbookCard(_ look: DiscoverViewModel.DiscoverLook) -> some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                if !look.garments.isEmpty {
                    LookSilhouetteView(
                        garments: look.garments,
                        frame: viewModel.frame,
                        onTapGarment: nil
                    )
                    .frame(maxHeight: AstraSize.silhouetteHeight * 0.65)
                    .allowsHitTesting(false)
                }

                Text(look.name)
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                if let description = look.description, !description.isEmpty {
                    Text(description)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func unlocksRail(_ products: [ProductUnlock]) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(String(localized: "Unlocks", comment: "Discover gap-fill product rail"))
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
            if products.isEmpty {
                Text(String(
                    localized: "Pieces that unlock looks with what you own show up here — from Shop and from links you paste.",
                    comment: "Discover Unlocks empty"
                ))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("discover.unlocks.empty")
            } else {
                ForEach(products) { item in
                    Button {
                        router.push(DiscoverRoute.productDecision(candidateID: item.candidate.id))
                    } label: {
                        unlockRow(item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("discover.unlocks.\(item.candidate.id.uuidString)")
                }
            }
        }
    }

    private func unlockRow(_ item: ProductUnlock) -> some View {
        AstraCard {
            HStack(alignment: .top, spacing: AstraSpacing.md) {
                AstraRemoteImage(
                    url: item.candidate.imageURL,
                    aspectRatio: 4.0 / 5.0,
                    thumbnail: .listRowThumbnail,
                    accessibilityDescription: item.candidate.name
                )
                .frame(width: 88)

                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(item.candidate.name)
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                    if let retailerLabel = item.candidate.retailerLabel {
                        Text(retailerLabel)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textMuted)
                    }
                    Text(unlockLine(item.outfitsUnlocked))
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func unlockLine(_ count: Int) -> String {
        String(
            localized: "Unlocks \(count) new outfits with what you own.",
            comment: "Discover Unlocks outfits-unlocked line"
        )
    }

    private func failed(_ error: AstraError) -> some View {
        VStack(spacing: AstraSpacing.md) {
            Text(error.message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
            if error.isRetryable {
                Button(String(localized: "Try Again", comment: "Retries Discover")) {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.astraSecondary)
            }
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiscoverEditorialRail: View {
    let title: String
    let guides: [DiscoverGuide]
    let identifier: String
    let onSelect: (DiscoverGuide) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .accessibilityIdentifier("\(identifier).heading")
            ForEach(guides) { guide in
                Button {
                    onSelect(guide)
                } label: {
                    editorialCard(guide)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(identifier).\(guide.id)")
            }
        }
    }

    private func editorialCard(_ guide: DiscoverGuide) -> some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(guide.title)
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                    Spacer(minLength: AstraSpacing.sm)
                    Text(String(localized: "\(guide.readingMinutes) min", comment: "Discover editorial estimated reading time"))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                }
                Text(guide.summary)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let season = guide.season {
                    Text(seasonLabel(season))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.accentChampagne)
                }
                if let label = guide.visibleCommercialLabel {
                    Text(label)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                        .accessibilityIdentifier("discover.editorial.commercial-label.\(guide.id)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func seasonLabel(_ season: String) -> String {
        let label: String
        switch season {
        case "summer": label = String(localized: "Warm weather", comment: "Seasonal tag")
        case "spring-fall": label = String(localized: "Spring and fall", comment: "Seasonal tag")
        default: label = season
        }
        return String(localized: "For \(label)", comment: "Discover seasonal guide season tag")
    }
}
