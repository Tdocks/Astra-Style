import Foundation
import SwiftData
import Testing
@testable import AstraStyle

@Suite("Offline product evaluation history")
struct ShoppingEvaluationCacheTests {
    @Test("evaluation and candidate snapshots are isolated by account")
    func ownerIsolation() async throws {
        let cache = makeCache()
        let ownerA = UUID()
        let ownerB = UUID()
        let candidate = makeCandidate(id: UUID())
        try await cache.store(candidate: candidate, ownerID: ownerA)
        try await cache.store(evaluation: makeEvaluation(owner: ownerA, candidate: candidate.id), candidate: candidate, ownerID: ownerA)
        try await cache.store(evaluation: makeEvaluation(owner: ownerB, candidate: candidate.id), candidate: candidate, ownerID: ownerB)

        let ownerADecision = try #require(await cache.cachedDecision(candidateID: candidate.id, ownerID: ownerA))
        let ownerBDecision = try #require(await cache.cachedDecision(candidateID: candidate.id, ownerID: ownerB))
        #expect(ownerADecision.candidate?.id == candidate.id)
        #expect(ownerADecision.evaluation.userID == ownerA)
        #expect(ownerBDecision.evaluation.userID == ownerB)
        #expect(try await cache.cachedRecentDecisions(ownerID: UUID(), limit: 10).isEmpty)
    }

    @Test("cached recent decisions retain the last 200 rows and order by evaluation time")
    func boundedRecentHistory() async throws {
        let cache = makeCache()
        let owner = UUID()
        for index in 0..<205 {
            let candidate = makeCandidate(id: UUID())
            let evaluatedAt = Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index))
            try await cache.store(
                evaluation: makeEvaluation(owner: owner, candidate: candidate.id, date: evaluatedAt),
                candidate: candidate,
                ownerID: owner
            )
        }

        let recent = try await cache.cachedRecentDecisions(ownerID: owner, limit: 500)
        #expect(recent.count == 200)
        #expect(recent.first?.evaluation.createdAt == Date(timeIntervalSince1970: 1_700_000_204))
        #expect(recent.last?.evaluation.createdAt == Date(timeIntervalSince1970: 1_700_000_005))
    }

    @Test("range reads are inclusive and hard account deletion purges only its rows")
    func rangeAndPurge() async throws {
        let cache = makeCache()
        let ownerA = UUID()
        let ownerB = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_100)
        let candidateA = makeCandidate(id: UUID())
        let candidateB = makeCandidate(id: UUID())
        try await cache.store(evaluation: makeEvaluation(owner: ownerA, candidate: candidateA.id, date: date), candidate: candidateA, ownerID: ownerA)
        try await cache.store(evaluation: makeEvaluation(owner: ownerB, candidate: candidateB.id, date: date), candidate: candidateB, ownerID: ownerB)

        #expect(try await cache.cachedEvaluations(from: date, to: date, ownerID: ownerA).map(\.productCandidateID) == [candidateA.id])
        try await cache.removeAll(ownerID: ownerA)
        #expect(try await cache.cachedRecentDecisions(ownerID: ownerA, limit: 10).isEmpty)
        #expect(try await cache.cachedRecentDecisions(ownerID: ownerB, limit: 10).count == 1)
    }

    @Test("a caller cannot write another owner's evaluation")
    func rejectsPeerEvaluation() async throws {
        let cache = makeCache()
        let owner = UUID()
        let peer = UUID()
        let candidate = makeCandidate(id: UUID())
        do {
            try await cache.store(evaluation: makeEvaluation(owner: peer, candidate: candidate.id), candidate: candidate, ownerID: owner)
            Issue.record("expected owner mismatch rejection")
        } catch let error as AstraError {
            #expect(error.category == .auth)
        }
        #expect(try await cache.cachedRecentDecisions(ownerID: owner, limit: 10).isEmpty)
    }

    @Test("a cached read fails if the active account changed while it was loading")
    func changedOwnerInvalidatesRead() {
        do {
            try LiveShoppingRepository.validateActiveOwner(expected: UUID(), actual: UUID())
            Issue.record("expected an account-change error")
        } catch let error as AstraError {
            #expect(error.category == .auth)
        } catch {
            Issue.record("expected an authentication error")
        }
    }

    private func makeCache() -> SwiftDataShoppingEvaluationCache {
        SwiftDataShoppingEvaluationCache(modelContainer: AstraModelContainer.preview())
    }

    private func makeCandidate(id: UUID) -> ProductCandidate {
        ProductCandidate(
            id: id,
            canonicalURL: URL(string: "https://shop.example/product/\(id.uuidString)") ?? URL(fileURLWithPath: "/"),
            retailer: "Fixture Shop",
            name: "Fixture coat",
            category: .outerwear,
            price: 100,
            currency: "USD"
        )
    }

    private func makeEvaluation(owner: UUID, candidate: UUID, date: Date = .now) -> ProductEvaluation {
        ProductEvaluation(
            userID: owner,
            productCandidateID: candidate,
            compatibilityScore: 80,
            redundancyScore: 20,
            outfitsUnlocked: 4,
            verdict: .consider,
            reasoning: "Fixture evaluation",
            createdAt: date
        )
    }
}
