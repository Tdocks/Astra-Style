import Foundation

/// The latest decision for a product. When shown from local storage, the
/// original evaluation timestamp is retained so the UI can label it as old.
public struct ProductDecisionSnapshot: Hashable, Sendable, Identifiable {
    public var id: UUID { evaluation.productCandidateID }
    public let candidate: ProductCandidate?
    public let evaluation: ProductEvaluation

    public init(candidate: ProductCandidate?, evaluation: ProductEvaluation) {
        self.candidate = candidate
        self.evaluation = evaluation
    }
}
