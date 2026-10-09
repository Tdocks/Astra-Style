import Foundation

/// A local read snapshot; deliberately has no method that can evaluate or
/// mutate a verdict. Fresh decisions always come from the server.
public protocol ShoppingEvaluationCaching: Sendable {
    func store(candidate: ProductCandidate, ownerID: UUID) async throws
    func store(evaluation: ProductEvaluation, candidate: ProductCandidate?, ownerID: UUID) async throws
    func cachedDecision(candidateID: UUID, ownerID: UUID) async throws -> ProductDecisionSnapshot?
    func cachedRecentDecisions(ownerID: UUID, limit: Int) async throws -> [ProductDecisionSnapshot]
    func cachedEvaluations(from: Date, to: Date, ownerID: UUID) async throws -> [ProductEvaluation]
    func removeAll(ownerID: UUID) async throws
}

public protocol ShoppingEvaluationCachePurging: Sendable {
    func purgeCachedShoppingEvaluations(ownerID: UUID) async throws
}
