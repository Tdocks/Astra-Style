//
//  KyraCardHydrator.swift
//  AstraStyle
//
//  Turns the id-reference cards in a Kyra response into drawable models
//  (`KyraRenderedCard`), one repository join per card kind.
//
//  A FAILED CARD COSTS THAT CARD, NEVER THE MESSAGE. The server already
//  guarantees that a card referencing an id nothing surfaced this turn is
//  dropped (guardrails.ts), so a fetch failure here is almost always
//  environmental — a dead connection, an endpoint not deployed yet, a row
//  deleted since the message was written. Failing the whole message over
//  it would throw away Kyra's actual words, which arrived fine; each
//  failure degrades to an `.unavailable` card that says what it is.
//
//  THE CLOSET IS FETCHED AT MOST ONCE PER CALL. Outfit cards need the
//  whole closet for the garment join (same reasoning as
//  `ClosetLooksViewModel`: a per-outfit fetch asks the server for the same
//  forty rows once per card). One response rarely carries two outfit
//  cards, but a packing answer legitimately can carry several.
//

import Foundation

public struct KyraCardHydrator: Sendable {
    private let outfitRepository: OutfitRepository
    private let closetRepository: ClosetRepository
    private let shoppingRepository: ShoppingRepository
    private let imageURLResolver: ClosetImageURLResolving
    private let lookHydrator: LookHydrator

    public init(
        outfitRepository: OutfitRepository,
        closetRepository: ClosetRepository,
        shoppingRepository: ShoppingRepository,
        imageURLResolver: ClosetImageURLResolving
    ) {
        self.outfitRepository = outfitRepository
        self.closetRepository = closetRepository
        self.shoppingRepository = shoppingRepository
        self.imageURLResolver = imageURLResolver
        self.lookHydrator = LookHydrator(
            closetRepository: closetRepository,
            imageURLResolver: imageURLResolver
        )
    }

    public func hydrate(_ cards: [KyraCard]) async -> [KyraRenderedCard] {
        guard !cards.isEmpty else { return [] }

        // Lazily fetched, shared across every outfit card in this response.
        var closet: [ClosetItem]?

        var rendered: [KyraRenderedCard] = []
        for card in cards {
            switch card {
            case .outfit(let outfitID):
                if closet == nil {
                    closet = try? await closetRepository.fetchItems()
                }
                rendered.append(await hydrateOutfit(outfitID: outfitID, closet: closet ?? []))
            case .closetItem(let closetItemID):
                rendered.append(await hydrateClosetItem(closetItemID: closetItemID))
            case .product(let productCandidateID):
                rendered.append(await hydrateProduct(productCandidateID: productCandidateID))
            case .comparisonTable(let table):
                rendered.append(.comparisonTable(id: UUID(), table: table))
            case .action(let action):
                rendered.append(.action(id: UUID(), action: action))
            }
        }
        return rendered
    }

    // MARK: - Per-kind joins

    private func hydrateOutfit(outfitID: UUID, closet: [ClosetItem]) async -> KyraRenderedCard {
        do {
            let outfit = try await outfitRepository.fetchOutfit(id: outfitID)
            let items = try await outfitRepository.fetchOutfitItems(outfitID: outfitID)
            let garments = await lookHydrator.hydrate(items: items, closet: closet)
            // An outfit whose garments all failed to join is a row pointing
            // at nothing (same rule as the Closet carousel) — saying "here
            // is an outfit" about a card with no clothes in it is the
            // confounded reading, so it degrades to unavailable instead.
            guard !garments.isEmpty else {
                return .unavailable(unavailableOutfit(id: outfitID, isRetryable: false))
            }
            return .outfit(KyraOutfitCardModel(outfit: outfit, garments: garments))
        } catch {
            return .unavailable(unavailableOutfit(id: outfitID, isRetryable: isRetryable(error)))
        }
    }

    private func hydrateClosetItem(closetItemID: UUID) async -> KyraRenderedCard {
        do {
            let item = try await closetRepository.fetchItem(id: closetItemID)
            let imageURL = await primaryImageURL(forItem: closetItemID)
            return .closetItem(KyraClosetItemCardModel(item: item, imageURL: imageURL))
        } catch {
            return .unavailable(KyraUnavailableCardModel(
                id: closetItemID,
                summary: String(
                    localized: "Kyra pointed at a closet piece that couldn't be loaded.",
                    comment: "Chat card shown when a referenced closet item failed to load"
                ),
                isRetryable: isRetryable(error)
            ))
        }
    }

    private func hydrateProduct(productCandidateID: UUID) async -> KyraRenderedCard {
        do {
            let evaluation = try await shoppingRepository.evaluateProduct(candidateID: productCandidateID)
            return .product(KyraProductCardModel(evaluation: evaluation))
        } catch {
            return .unavailable(KyraUnavailableCardModel(
                id: productCandidateID,
                summary: String(
                    localized: "Kyra mentioned a product whose details couldn't be loaded.",
                    comment: "Chat card shown when a referenced product failed to load"
                ),
                isRetryable: isRetryable(error)
            ))
        }
    }

    // MARK: - Helpers

    /// The item's display image, resolved the same way `LookHydrator` does
    /// it for outfits: primary image first, any image second, and a missing
    /// picture degrades to the labelled no-photo state — never a missing
    /// garment.
    private func primaryImageURL(forItem itemID: UUID) async -> URL? {
        let images = (try? await closetRepository.fetchImages(forItem: itemID)) ?? []
        guard let path = (images.first { $0.isPrimary } ?? images.first)?.displayStoragePath else {
            return nil
        }
        return try? await imageURLResolver.resolve(storagePath: path)
    }

    private func unavailableOutfit(id: UUID, isRetryable: Bool) -> KyraUnavailableCardModel {
        KyraUnavailableCardModel(
            id: id,
            summary: String(
                localized: "Kyra built a look here that couldn't be loaded.",
                comment: "Chat card shown when a referenced outfit failed to load"
            ),
            isRetryable: isRetryable
        )
    }

    private func isRetryable(_ error: Error) -> Bool {
        (error as? AstraError)?.isRetryable ?? false
    }
}
