//
//  StoreKitPurchasing.swift
//  AstraStyle
//
//  StoreKit 2 lives behind this seam so PaywallViewModel tests do not
//  need a device or a .storekit file. The live adapter maps a verified
//  Transaction onto AppStoreTransactionPayload; the repository then
//  syncs that to the server (ADR 0009: device is not entitlement truth).
//

import Foundation
import StoreKit

public struct PaywallOffering: Equatable, Sendable, Identifiable {
    public var id: AstraProductID
    public var displayName: String
    public var displayPrice: String

    public init(id: AstraProductID, displayName: String, displayPrice: String) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
    }
}

public protocol StoreKitPurchasing: Sendable {
    func offerings() async throws -> [PaywallOffering]
    func purchase(_ productID: AstraProductID) async throws -> AppStoreTransactionPayload?
    func restoreEntitlements() async throws -> [AppStoreTransactionPayload]
}

public struct LiveStoreKitPurchasing: StoreKitPurchasing {
    public init() {}

    public func offerings() async throws -> [PaywallOffering] {
        let ids = Set(AstraProductID.allCases.map(\.rawValue))
        let products = try await Product.products(for: ids)
        return AstraProductID.allCases.compactMap { id in
            guard let product = products.first(where: { $0.id == id.rawValue }) else { return nil }
            return PaywallOffering(
                id: id,
                displayName: product.displayName,
                displayPrice: product.displayPrice
            )
        }
    }

    public func purchase(_ productID: AstraProductID) async throws -> AppStoreTransactionPayload? {
        let products = try await Product.products(for: [productID.rawValue])
        guard let product = products.first else {
            throw AstraError.unimplemented("That Premium plan is not configured on this App Store account.")
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try Self.verified(verification)
            let payload = Self.payload(from: transaction)
            await transaction.finish()
            return payload
        case .userCancelled, .pending:
            return nil
        @unknown default:
            return nil
        }
    }

    public func restoreEntitlements() async throws -> [AppStoreTransactionPayload] {
        try await AppStore.sync()
        var payloads: [AppStoreTransactionPayload] = []
        for await verification in Transaction.currentEntitlements {
            let transaction = try Self.verified(verification)
            payloads.append(Self.payload(from: transaction))
        }
        return payloads
    }

    private static func verified(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .unverified:
            throw AstraError.validation("Apple could not verify that purchase.")
        case .verified(let transaction):
            return transaction
        }
    }

    private static func payload(from transaction: Transaction) -> AppStoreTransactionPayload {
        let environment: SubscriptionEnvironment = transaction.environment == .production
            ? .production
            : .sandbox
        return AppStoreTransactionPayload(
            originalTransactionID: String(transaction.originalID),
            transactionID: String(transaction.id),
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expiresDate: transaction.expirationDate,
            environment: environment
        )
    }
}

public struct MockStoreKitPurchasing: StoreKitPurchasing, Sendable {
    public var offeringsToReturn: [PaywallOffering]
    public var purchasePayload: AppStoreTransactionPayload?
    public var restorePayloads: [AppStoreTransactionPayload]
    public var purchaseError: AstraError?

    public init(
        offerings: [PaywallOffering] = [
            PaywallOffering(id: .monthly, displayName: "Premium Monthly", displayPrice: "$12.99"),
            PaywallOffering(id: .annual, displayName: "Premium Annual", displayPrice: "$79.99")
        ],
        purchasePayload: AppStoreTransactionPayload? = AppStoreTransactionPayload(
            originalTransactionID: "orig-test",
            transactionID: "tx-test",
            productID: AstraProductID.monthly.rawValue,
            purchaseDate: Date(timeIntervalSince1970: 1_777_000_000),
            expiresDate: Date(timeIntervalSince1970: 1_779_600_000),
            environment: .sandbox
        ),
        restorePayloads: [AppStoreTransactionPayload] = []
    ) {
        self.offeringsToReturn = offerings
        self.purchasePayload = purchasePayload
        self.restorePayloads = restorePayloads
    }

    public func offerings() async throws -> [PaywallOffering] { offeringsToReturn }

    public func purchase(_ productID: AstraProductID) async throws -> AppStoreTransactionPayload? {
        if let purchaseError { throw purchaseError }
        guard var payload = purchasePayload else { return nil }
        payload.productID = productID.rawValue
        return payload
    }

    public func restoreEntitlements() async throws -> [AppStoreTransactionPayload] {
        restorePayloads
    }
}
