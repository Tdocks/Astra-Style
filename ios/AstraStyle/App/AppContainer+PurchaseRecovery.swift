import Foundation

extension AppContainer {
    private var usesLivePurchaseRecovery: Bool {
        #if DEBUG
        return !AstraFeatureFlags.usesMockBackend && !AstraEnvironment.current.isLocalQABackend
        #else
        return true
        #endif
    }

    func observePurchaseTransactions() async {
        guard usesLivePurchaseRecovery else { return }
        await purchaseTransactionObserver.observe()
    }

    func recoverUnfinishedPurchases() async {
        guard usesLivePurchaseRecovery else { return }
        await purchaseTransactionObserver.reconcileUnfinished()
    }
}
