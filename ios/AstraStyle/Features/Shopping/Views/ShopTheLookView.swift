import SwiftUI

struct ShopTheLookView: View {
    @State private var viewModel: ShopTheLookViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: ShopTheLookViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView().tint(AstraColor.accentChampagne)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                failure(error)
            case .loaded(let look):
                content(look)
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Shop this look", comment: "Full look shopping screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
    }

    private func content(_ look: ShopTheLookViewModel.Loaded) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                outfitPreview(look)
                ownedSection(look)
                missingSection(look)
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("shopTheLook.content")
    }

    @ViewBuilder
    private func outfitPreview(_ look: ShopTheLookViewModel.Loaded) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(look.outfit.name)
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)
            if let preview = look.outfit.generatedPreviewURL {
                AstraRemoteImage(
                    url: preview,
                    aspectRatio: 4.0 / 5.0,
                    accessibilityDescription: look.outfit.name
                )
                .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card))
                HStack(spacing: AstraSpacing.xs) {
                    Image(systemName: "info.circle")
                    Text(String(localized: "Generated preview · an estimate", comment: "Disclaimer on generated outfit image"))
                }
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
            } else {
                AstraCard {
                    VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                        Label(
                            String(localized: "Outfit preview", comment: "Preview label when no generated image exists"),
                            systemImage: "square.grid.2x2"
                        )
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                        ScrollView(.horizontal) {
                            HStack(spacing: AstraSpacing.xs) {
                                ForEach(look.ownedPieces) { piece in
                                    previewTile(url: piece.imageURL, label: piece.item.name, owned: true)
                                }
                                ForEach(look.missingPieces) { piece in
                                    previewTile(url: piece.candidate?.imageURL, label: piece.candidate?.name ?? categoryName(piece.role), owned: false)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        Text(String(localized: "These are the pieces attached to this saved look; no generated preview image is stored.", comment: "Honest no-generated-image caption"))
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textMuted)
                    }
                }
            }
        }
        .accessibilityIdentifier("shopTheLook.preview")
    }

    private func previewTile(url: URL?, label: String, owned: Bool) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            ZStack(alignment: .topTrailing) {
                if let url {
                    AstraRemoteImage(
                        url: url,
                        aspectRatio: 1,
                        thumbnail: .listRowThumbnail,
                        accessibilityDescription: label
                    )
                } else {
                    RoundedRectangle(cornerRadius: AstraRadius.small)
                        .fill(AstraColor.surfaceElevated)
                        .overlay {
                            Image(systemName: owned ? "tshirt" : "bag")
                                .astraIcon(.control)
                                .foregroundStyle(AstraColor.textMuted)
                        }
                }
                Image(systemName: owned ? "checkmark.circle.fill" : "plus.circle.fill")
                    .astraIcon(.inline)
                    .foregroundStyle(owned ? AstraColor.successOlive : AstraColor.accentChampagneAccessible)
                    .padding(AstraSpacing.xxs)
            }
            .frame(width: AstraSpacing.unit * 16, height: AstraSpacing.unit * 16)
            .clipShape(RoundedRectangle(cornerRadius: AstraRadius.small))
            Text(label)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .lineLimit(1)
                .frame(width: AstraSpacing.unit * 16, alignment: .leading)
        }
    }

    private func ownedSection(_ look: ShopTheLookViewModel.Loaded) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: String(localized: "Already in your wardrobe", comment: "Owned items section"))
            if look.ownedPieces.isEmpty {
                Text(String(localized: "No owned pieces could be matched to this look.", comment: "Empty owned outfit items"))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .accessibilityIdentifier("shopTheLook.owned.empty")
            } else {
                ForEach(look.ownedPieces) { piece in
                    ownedRow(piece)
                }
            }
            if look.unresolvedOwnedCount > 0 {
                Text(String(localized: "Some saved wardrobe pieces could not be loaded. They are not shown as products to buy.", comment: "Unresolved owned item fail-safe"))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .accessibilityIdentifier("shopTheLook.owned.unresolved")
            }
        }
        .accessibilityIdentifier("shopTheLook.owned")
    }

    private func ownedRow(_ piece: ShopTheLookViewModel.OwnedPiece) -> some View {
        AstraCard {
            HStack(spacing: AstraSpacing.md) {
                AstraRemoteImage(
                    url: piece.imageURL,
                    aspectRatio: 1,
                    thumbnail: .listRowThumbnail,
                    accessibilityDescription: piece.item.name
                )
                .frame(width: 64)
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(piece.item.name).astraText(.callout).foregroundStyle(AstraColor.textPrimary)
                    Text(categoryName(piece.role)).astraText(.caption).foregroundStyle(AstraColor.textMuted)
                    Label(String(localized: "Owned", comment: "Owned outfit item badge"), systemImage: "checkmark.circle.fill")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.successOlive)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("shopTheLook.ownedItem.\(piece.id.uuidString.lowercased())")
    }

    private func missingSection(_ look: ShopTheLookViewModel.Loaded) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: String(localized: "Pieces to complete the look", comment: "Missing items section"))
            if look.missingPieces.isEmpty {
                Text(String(localized: "No researched products are attached to this saved look yet. Browse Shop separately to explore the catalog.", comment: "Honest empty researched products state"))
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shopTheLook.missing.empty")
                Button {
                    router.popToRoot(for: .shop)
                } label: {
                    Text(String(localized: "Browse Shop catalog", comment: "Catalog navigation from empty Shop the Look"))
                        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                }
                .buttonStyle(.astraSecondary)
                .accessibilityIdentifier("shopTheLook.browseCatalog")
            } else {
                ForEach(look.missingPieces) { piece in
                    missingRow(piece)
                }
            }
        }
        .accessibilityIdentifier("shopTheLook.missing")
    }

    @ViewBuilder
    private func missingRow(_ piece: ShopTheLookViewModel.MissingPiece) -> some View {
        ShopTheLookMissingProductCard(piece: piece) { candidateID in
            router.push(ShopRoute.productDecision(candidateID: candidateID))
        }
        .accessibilityIdentifier("shopTheLook.missingItem.\(piece.id.uuidString.lowercased())")
    }

    private func failure(_ error: AstraError) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            Text(error.message).astraText(.body).foregroundStyle(AstraColor.textSecondary)
            Button(String(localized: "Try again", comment: "Retry Shop the Look")) {
                Task { await viewModel.retry() }
            }
        }
        .padding(AstraSpacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func categoryName(_ role: OutfitItemRole) -> String {
        ClothingCategory(rawValue: role.rawValue)?.displayName ?? role.rawValue
    }
}
