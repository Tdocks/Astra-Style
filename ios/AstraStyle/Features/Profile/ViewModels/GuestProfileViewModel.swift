//
//  GuestProfileViewModel.swift
//  AstraStyle
//
//  Backs `GuestProfileView`, the Profile tab's real (non-placeholder)
//  surface for a guest session (spec §6.2; ADR 0011): how many of the
//  10-item guest cap they've used, and the route to create an account —
//  the "real path forward" a guest needs once they hit the cap, reachable
//  independent of whichever screen actually triggered
//  `GuestClosetError.capReached`.
//

import Foundation

@MainActor
@Observable
public final class GuestProfileViewModel {
    public enum LoadState: Equatable {
        case loading
        case loaded(itemCount: Int)
        case error(String)
    }

    public private(set) var state: LoadState = .loading

    private let closetRepository: ClosetRepository

    public init(closetRepository: ClosetRepository) {
        self.closetRepository = closetRepository
    }

    public var itemCount: Int {
        if case .loaded(let count) = state { return count }
        return 0
    }

    public var isAtCap: Bool { itemCount >= GuestLimits.maxClosetItems }

    public func load() async {
        state = .loading
        do {
            // Goes through the same `ClosetRepository` every other feature
            // uses — `GuestAwareClosetRepository` routes this to local
            // storage for a guest session, so this call makes no network
            // request either.
            let items = try await closetRepository.fetchItems()
            state = .loaded(itemCount: items.count)
        } catch let error as AstraError {
            state = .error(error.message)
        } catch {
            state = .error(String(localized: "Couldn't load your guest closet."))
        }
    }
}
