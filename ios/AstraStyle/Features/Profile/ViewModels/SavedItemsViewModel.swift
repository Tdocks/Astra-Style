//
//  SavedItemsViewModel.swift
//  AstraStyle
//
//  Profile wishlist browser — saved pieces open Product Decision.
//

import Foundation
import Observation

@MainActor
@Observable
public final class SavedItemsViewModel {
    public enum ViewState: Sendable {
        case loading
        case loaded([ProductCandidate])
        case empty
        case failed(AstraError)
    }

    public private(set) var state: ViewState = .loading

    private let shoppingRepository: ShoppingRepository

    public init(shoppingRepository: ShoppingRepository) {
        self.shoppingRepository = shoppingRepository
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
            let items = try await shoppingRepository.fetchWishlist()
            state = items.isEmpty ? .empty : .loaded(items)
        } catch let error as AstraError {
            state = .failed(error)
        } catch {
            state = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }
}
