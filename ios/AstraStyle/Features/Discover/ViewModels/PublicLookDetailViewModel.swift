//
//  PublicLookDetailViewModel.swift
//  AstraStyle
//
//  Loads the sanitized public-look summary and garments without fetching the
//  peer's raw outfits, outfit_items, or closet_items rows.
//

import Foundation
import Observation

@MainActor
@Observable
public final class PublicLookDetailViewModel {
    public enum ViewState {
        case loading
        case loaded(PublicWornLook, [LookGarment])
        case failed(AstraError)
    }

    public private(set) var state: ViewState = .loading
    public private(set) var isReporting = false

    private let outfitID: UUID
    private let outfitRepository: OutfitRepository
    private let imageURLResolver: ClosetImageURLResolving

    public init(
        outfitID: UUID,
        outfitRepository: OutfitRepository,
        imageURLResolver: ClosetImageURLResolving
    ) {
        self.outfitID = outfitID
        self.outfitRepository = outfitRepository
        self.imageURLResolver = imageURLResolver
    }

    public func onAppear() async {
        guard case .loading = state else { return }
        await load()
    }

    public func refresh() async {
        await load()
    }

    public func report() async throws {
        guard !isReporting else { return }
        isReporting = true
        defer { isReporting = false }
        try await outfitRepository.reportLookbook(outfitID: outfitID)
    }

    private func load() async {
        state = .loading
        do {
            async let lookTask = outfitRepository.fetchPublicWornLook(id: outfitID)
            async let garmentsTask = outfitRepository.fetchPublicLookGarments(outfitIDs: [outfitID])
            let look = try await lookTask
            let rows = try await garmentsTask
            let references = rows.compactMap { row -> PublicLookImageReference? in
                guard let imageID = row.displayImageID else { return nil }
                return PublicLookImageReference(
                    outfitID: row.outfitID,
                    closetItemID: row.closetItemID,
                    imageID: imageID
                )
            }
            let urls = try await imageURLResolver.resolve(publicLookImages: references)
            let garments = rows.map { row in
                let item = LookGarmentItem(
                    id: row.closetItemID,
                    name: row.name,
                    brand: row.brand,
                    category: row.category,
                    formalityScore: row.formalityScore
                )
                return LookGarment(
                    item: item,
                    role: row.role,
                    imageURL: row.displayImageID.flatMap { urls[$0] }
                )
            }
            state = .loaded(look, garments)
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError.server("Couldn't load that shared look."))
        }
    }
}
