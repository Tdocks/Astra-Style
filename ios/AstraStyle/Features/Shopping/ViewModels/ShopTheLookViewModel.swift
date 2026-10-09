import Foundation
import Observation

/// Owner-scoped read model for spec §6.18. A missing product is shown only
/// when a saved `outfit_items` row carries its real `product_candidate_id`;
/// empty roles are never mapped to guessed catalog products.
@MainActor
@Observable
final class ShopTheLookViewModel {
    struct OwnedPiece: Identifiable, Sendable {
        let item: ClosetItem
        let role: OutfitItemRole
        let imageURL: URL?
        var id: UUID { item.id }
    }

    struct MissingPiece: Identifiable, Sendable {
        let slotID: UUID
        let role: OutfitItemRole
        let candidate: ProductCandidate?
        var id: UUID { slotID }

        var affiliateDisclosure: String {
            ShopTheLookPresentation.affiliateDisclosure(for: candidate)
        }

        var availableSizes: [String] {
            ShopTheLookPresentation.availableSizes(from: candidate)
        }
    }

    struct Loaded: Sendable {
        let outfit: Outfit
        let ownedPieces: [OwnedPiece]
        let missingPieces: [MissingPiece]
        let unresolvedOwnedCount: Int
    }

    enum State {
        case loading
        case loaded(Loaded)
        case failed(AstraError)
    }

    private(set) var state: State = .loading

    private let outfitID: UUID
    private let outfitRepository: OutfitRepository
    private let closetRepository: ClosetRepository
    private let profileRepository: ProfileRepository
    private let shoppingRepository: ShoppingRepository
    private let imageURLResolver: ClosetImageURLResolving
    private let currentOwnerID: @Sendable () async -> UUID?

    init(
        outfitID: UUID,
        outfitRepository: OutfitRepository,
        closetRepository: ClosetRepository,
        profileRepository: ProfileRepository,
        shoppingRepository: ShoppingRepository,
        imageURLResolver: ClosetImageURLResolving,
        currentOwnerID: @escaping @Sendable () async -> UUID?
    ) {
        self.outfitID = outfitID
        self.outfitRepository = outfitRepository
        self.closetRepository = closetRepository
        self.profileRepository = profileRepository
        self.shoppingRepository = shoppingRepository
        self.imageURLResolver = imageURLResolver
        self.currentOwnerID = currentOwnerID
    }

    func onAppear() async {
        guard case .loading = state else { return }
        await load()
    }

    func retry() async {
        state = .loading
        await load()
    }

    private func load() async {
        do {
            let profile = try await profileRepository.fetchCurrentProfile()
            try await requireActiveOwner(profile.id)
            let outfit = try await outfitRepository.fetchOutfit(id: outfitID)
            try await requireActiveOwner(profile.id)
            guard outfit.userID == profile.id else {
                throw AstraError.auth("This look is not available to this account.")
            }
            let look = try await makeLook(outfit, ownerID: profile.id)
            try await requireActiveOwner(profile.id)
            state = .loaded(look)
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }

    private func makeLook(_ outfit: Outfit, ownerID: UUID) async throws -> Loaded {
        let outfitItems = try await outfitRepository.fetchOutfitItems(outfitID: outfitID)
            .sorted { $0.sortOrder < $1.sortOrder }
        try await requireActiveOwner(ownerID)
        guard outfitItems.allSatisfy({ $0.outfitID == outfitID }) else {
            throw AstraError.auth("The saved look includes unrelated item data.")
        }
        let closetItems = try await closetRepository.fetchItems()
        try await requireActiveOwner(ownerID)
        guard closetItems.allSatisfy({ $0.userID == ownerID }) else {
            throw AstraError.auth("The wardrobe data belongs to another account.")
        }
        let closetByID = Dictionary(uniqueKeysWithValues: closetItems.map { ($0.id, $0) })
        let ownedRows = outfitItems.compactMap { row -> (OutfitItem, ClosetItem)? in
            guard let id = row.closetItemID, let item = closetByID[id] else { return nil }
            return (row, item)
        }
        let unresolvedOwnedCount = outfitItems.filter { $0.closetItemID != nil }.count - ownedRows.count
        let imageURLs = try await resolveImageURLs(for: ownedRows.map(\.1), ownerID: ownerID)
        try await requireActiveOwner(ownerID)
        let ownedPieces = ownedRows.map { pair in
            OwnedPiece(item: pair.1, role: pair.0.role, imageURL: imageURLs[pair.1.id])
        }

        let missingRows = outfitItems.filter { $0.closetItemID == nil && $0.productCandidateID != nil }
        var candidatesByID: [UUID: ProductCandidate] = [:]
        for row in missingRows {
            guard let candidateID = row.productCandidateID else { continue }
            let candidate = try? await shoppingRepository.fetchProductCandidate(id: candidateID)
            try await requireActiveOwner(ownerID)
            if let candidate { candidatesByID[candidateID] = candidate }
        }
        try await requireActiveOwner(ownerID)
        return Loaded(
            outfit: outfit,
            ownedPieces: ownedPieces,
            missingPieces: ShopTheLookPresentation.missingPieces(from: outfitItems, candidatesByID: candidatesByID),
            unresolvedOwnedCount: unresolvedOwnedCount
        )
    }

    private func resolveImageURLs(for items: [ClosetItem], ownerID: UUID) async throws -> [UUID: URL] {
        guard !items.isEmpty else { return [:] }
        var pathByID: [UUID: String] = [:]
        for item in items {
            let images = try? await closetRepository.fetchImages(forItem: item.id)
            try await requireActiveOwner(ownerID)
            guard let images, let image = images.first(where: \.isPrimary) ?? images.first else { continue }
            pathByID[item.id] = image.displayStoragePath
        }
        guard !pathByID.isEmpty else { return [:] }
        let urls = try? await imageURLResolver.resolve(storagePaths: Array(pathByID.values))
        try await requireActiveOwner(ownerID)
        guard let urls else { return [:] }
        return pathByID.compactMapValues { urls[$0] }
    }

    private func requireActiveOwner(_ expectedOwnerID: UUID) async throws {
        guard await currentOwnerID() == expectedOwnerID else {
            throw AstraError.auth("Your account changed while this look was loading. Reopen it to continue.")
        }
    }
}

enum ShopTheLookPresentation {
    static func missingPieces(
        from outfitItems: [OutfitItem],
        candidatesByID: [UUID: ProductCandidate]
    ) -> [ShopTheLookViewModel.MissingPiece] {
        outfitItems
            .filter { $0.closetItemID == nil && $0.productCandidateID != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { row in
                guard let candidateID = row.productCandidateID else { return nil }
                // A mismatched role is unavailable; it is not safe to show a
                // real product as a match for another garment slot.
                let candidate = self.candidate(candidatesByID[candidateID], matches: row.role)
                return ShopTheLookViewModel.MissingPiece(slotID: row.id, role: row.role, candidate: candidate)
            }
    }

    static func candidate(_ candidate: ProductCandidate?, matches role: OutfitItemRole) -> ProductCandidate? {
        guard candidate?.category.rawValue == role.rawValue else { return nil }
        return candidate
    }

    static func availableSizes(from candidate: ProductCandidate?) -> [String] {
        guard case .object(let availability)? = candidate?.availability,
              case .array(let values)? = availability["sizes"] else { return [] }
        return values.compactMap { value in
            guard case .string(let size) = value else { return nil }
            let trimmed = size.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    static func affiliateDisclosure(for candidate: ProductCandidate?) -> String {
        guard let candidate else { return "Product details are unavailable; no retailer link is shown." }
        if candidate.affiliateURL != nil {
            return "Affiliate link: Astra Style may earn a commission if you buy through this link."
        }
        return "No affiliate link is attached to this product."
    }
}
