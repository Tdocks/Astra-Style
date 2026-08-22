//
//  ProductLinkPasteViewModel.swift
//  AstraStyle
//
//  Home's paste door. Extract is the only call here; evaluate happens on
//  the decision page so a cached sheet cannot age a verdict.
//

import Foundation
import Observation

enum ProductLinkURL {
    /// Scheme + host only. The extractor decides whether the page is a product.
    static func parse(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host() != nil else { return nil }
        return url
    }
}

@MainActor
@Observable
public final class ProductLinkPasteViewModel {
    public private(set) var isSubmitting = false
    public private(set) var submitError: AstraError?

    private let shoppingRepository: ShoppingRepository

    public init(shoppingRepository: ShoppingRepository) {
        self.shoppingRepository = shoppingRepository
    }

    public func extract(from raw: String) async -> UUID? {
        guard let url = ProductLinkURL.parse(raw) else {
            submitError = AstraError.validation("Paste a product page URL.")
            return nil
        }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        do {
            let candidate = try await shoppingRepository.extractProduct(from: url)
            return candidate.id
        } catch let error as AstraError {
            submitError = error
            return nil
        } catch {
            submitError = AstraError(category: .unknown, message: error.localizedDescription)
            return nil
        }
    }

    public func clearError() {
        submitError = nil
    }
}
