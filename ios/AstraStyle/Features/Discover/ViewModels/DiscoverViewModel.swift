//
//  DiscoverViewModel.swift
//  AstraStyle
//
//  Wave F: lookbooks from HIS closet — saved outfits, not a CMS grid and
//  not a retailer feed. Unlock number lives on the paste-a-link door (D);
//  this page only shows looks he already has.
//

import Foundation
import Observation

@MainActor
@Observable
public final class DiscoverViewModel {
    public enum ViewState: Sendable {
        case loading
        case loaded([Outfit])
        case empty
        case failed(AstraError)
    }

    public private(set) var state: ViewState = .loading

    private let outfitRepository: OutfitRepository

    public init(outfitRepository: OutfitRepository) {
        self.outfitRepository = outfitRepository
    }

    public func onAppear() async {
        guard case .loading = state else { return }
        await load()
    }

    public func refresh() async {
        await load()
    }

    private func load() async {
        do {
            let looks = try await outfitRepository.fetchOutfits().filter { !$0.isArchived }
            state = looks.isEmpty ? .empty : .loaded(looks)
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }
}
