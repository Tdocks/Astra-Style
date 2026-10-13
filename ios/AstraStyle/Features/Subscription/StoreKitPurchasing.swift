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
    func finishTransaction(_ payload: AppStoreTransactionPayload) async
}

extension StoreKitPurchasing {
    public func finishTransaction(_ payload: AppStoreTransactionPayload) async {}
}

public struct LiveStoreKitPurchasing: StoreKitPurchasing {
    private let appAccountTokenProvider: @Sendable () async -> UUID?
    private let restoreSync: @Sendable () async throws -> Void

    public init(appAccountTokenProvider: @escaping @Sendable () async -> UUID? = { nil }) {
        self.appAccountTokenProvider = appAccountTokenProvider
        self.restoreSync = { try await AppStore.sync() }
    }

    init(appAccountTokenProvider: @escaping @Sendable () async -> UUID?,
         restoreSync: @escaping @Sendable () async throws -> Void) {
        self.appAccountTokenProvider = appAccountTokenProvider
        self.restoreSync = restoreSync
    }

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
        let result: Product.PurchaseResult
        if let appAccountToken = await appAccountTokenProvider() {
            result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
        } else {
            result = try await product.purchase()
        }
        switch result {
        case .success(let verification):
            let transaction = try Self.verifiedTransaction(from: verification)
            let payload = Self.payload(from: transaction.transaction, signedInfo: transaction.signedInfo)
            return payload
        case .userCancelled, .pending:
            return nil
        @unknown default:
            return nil
        }
    }

    public func restoreEntitlements() async throws -> [AppStoreTransactionPayload] {
        try await restoreSync()
        var payloads: [AppStoreTransactionPayload] = []
        for await verification in Transaction.currentEntitlements {
            let transaction = try Self.verifiedTransaction(from: verification)
            let verified = transaction.transaction
            guard verified.revocationDate == nil, !verified.isUpgraded,
                  verified.expirationDate.map({ $0 > .now }) ?? true else { continue }
            payloads.append(Self.payload(from: verified, signedInfo: transaction.signedInfo))
        }
        return payloads
    }

    public func finishTransaction(_ payload: AppStoreTransactionPayload) async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result,
                  String(transaction.id) == payload.transactionID else { continue }
            await transaction.finish()
            return
        }
    }

    static func verifiedTransaction(
        from result: VerificationResult<Transaction>
    ) throws -> (transaction: Transaction, signedInfo: String) {
        switch result {
        case .unverified:
            throw AstraError.validation("Apple could not verify that purchase.")
        case .verified(let transaction):
            return (transaction, result.jwsRepresentation)
        }
    }

    static func payload(
        from transaction: Transaction,
        signedInfo: String
    ) -> AppStoreTransactionPayload {
        let environment: SubscriptionEnvironment = transaction.environment == .production
            ? .production
            : .sandbox
        return AppStoreTransactionPayload(
            originalTransactionID: String(transaction.originalID),
            transactionID: String(transaction.id),
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expiresDate: transaction.expirationDate,
            environment: environment,
            signedTransactionInfo: signedInfo
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
            purchaseDate: .now,
            expiresDate: .now.addingTimeInterval(30 * 24 * 60 * 60),
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
