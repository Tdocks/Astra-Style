import Foundation
import SwiftData

@ModelActor
public actor SwiftDataShoppingEvaluationCache: ShoppingEvaluationCaching {
    private let maximumRecentEvaluationRows = 200
    private let maximumCandidateRows = 100

    public func store(candidate: ProductCandidate, ownerID: UUID) async throws {
        let row = try row(for: candidate.id, ownerID: ownerID)
        row.encodedCandidate = try JSONEncoder().encode(candidate)
        row.updatedAt = .now
        try modelContext.save()
        try prune(ownerID: ownerID)
    }

    public func store(
        evaluation: ProductEvaluation,
        candidate: ProductCandidate?,
        ownerID: UUID
    ) async throws {
        guard evaluation.userID == ownerID else {
            throw AstraError.auth("A shopping evaluation belongs to another account.")
        }
        guard candidate == nil || candidate?.id == evaluation.productCandidateID else {
            throw AstraError.validation("The product does not match its evaluation.")
        }
        let row = try row(for: evaluation, ownerID: ownerID)
        row.encodedEvaluation = try JSONEncoder().encode(evaluation)
        row.evaluatedAt = evaluation.createdAt
        row.updatedAt = .now
        if let candidate { row.encodedCandidate = try JSONEncoder().encode(candidate) }
        try modelContext.save()
        if let candidate { try await store(candidate: candidate, ownerID: ownerID) }
        try prune(ownerID: ownerID)
    }

    public func cachedDecision(candidateID: UUID, ownerID: UUID) async throws -> ProductDecisionSnapshot? {
        let rows = try ownerRows(ownerID: ownerID).filter { $0.candidateID == candidateID }
        let evaluationRow = rows
            .filter { $0.encodedEvaluation != nil }
            .max { ($0.evaluatedAt ?? .distantPast) < ($1.evaluatedAt ?? .distantPast) }
        guard let evaluationRow, let data = evaluationRow.encodedEvaluation else { return nil }
        let candidateRow = try rowIfPresent(for: candidateID, ownerID: ownerID)
        return try decision(from: evaluationRow, candidateRow: candidateRow, evaluationData: data)
    }

    public func cachedRecentDecisions(ownerID: UUID, limit: Int) async throws -> [ProductDecisionSnapshot] {
        guard limit > 0 else { return [] }
        var seen: Set<UUID> = []
        let rows = try ownerRows(ownerID: ownerID)
            .filter { $0.encodedEvaluation != nil && $0.evaluatedAt != nil }
            .sorted { ($0.evaluatedAt ?? .distantPast) > ($1.evaluatedAt ?? .distantPast) }
            .filter { seen.insert($0.candidateID).inserted }
            .prefix(min(limit, maximumRecentEvaluationRows))
        return try rows.compactMap { row in
            guard let data = row.encodedEvaluation else { return nil }
            let candidateRow = try rowIfPresent(for: row.candidateID, ownerID: ownerID)
            return try decision(from: row, candidateRow: candidateRow, evaluationData: data)
        }
    }

    public func cachedEvaluations(from: Date, to: Date, ownerID: UUID) async throws -> [ProductEvaluation] {
        guard from <= to else { throw AstraError.validation("That evaluation period is invalid.") }
        return try ownerRows(ownerID: ownerID)
            .filter { row in
                guard row.encodedEvaluation != nil, let evaluatedAt = row.evaluatedAt else { return false }
                return evaluatedAt >= from && evaluatedAt <= to
            }
            .compactMap { row in
                guard let data = row.encodedEvaluation else { return nil }
                let evaluation = try JSONDecoder().decode(ProductEvaluation.self, from: data)
                guard evaluation.userID == ownerID, evaluation.productCandidateID == row.candidateID else {
                    throw AstraError.server("A saved product decision couldn't be read.")
                }
                return evaluation
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func removeAll(ownerID: UUID) async throws {
        for row in try ownerRows(ownerID: ownerID) { modelContext.delete(row) }
        try modelContext.save()
    }

    private func row(for candidateID: UUID, ownerID: UUID) throws -> PersistedProductEvaluation {
        if let existing = try rowIfPresent(for: candidateID, ownerID: ownerID) { return existing }
        let created = PersistedProductEvaluation(ownerID: ownerID, candidateID: candidateID)
        modelContext.insert(created)
        return created
    }

    private func row(for evaluation: ProductEvaluation, ownerID: UUID) throws -> PersistedProductEvaluation {
        let matches = try ownerRows(ownerID: ownerID).filter { row in
            row.candidateID == evaluation.productCandidateID && row.encodedEvaluation != nil &&
                row.evaluatedAt == evaluation.createdAt
        }
        for row in matches {
            if let data = row.encodedEvaluation,
               try JSONDecoder().decode(ProductEvaluation.self, from: data) == evaluation {
                return row
            }
        }
        let base = evaluationCacheID(
            ownerID: ownerID,
            candidateID: evaluation.productCandidateID,
            evaluatedAt: evaluation.createdAt
        )
        let uniqueKey = matches.isEmpty ? base : "\(base):\(UUID().uuidString.lowercased())"
        let created = PersistedProductEvaluation(
            ownerID: ownerID,
            candidateID: evaluation.productCandidateID,
            cacheID: uniqueKey
        )
        modelContext.insert(created)
        return created
    }

    private func evaluationCacheID(ownerID: UUID, candidateID: UUID, evaluatedAt: Date) -> String {
        let timestamp = String(format: "%.6f", evaluatedAt.timeIntervalSince1970)
        return "\(ownerID.uuidString.lowercased()):\(candidateID.uuidString.lowercased()):\(timestamp)"
    }

    private func rowIfPresent(for candidateID: UUID, ownerID: UUID) throws -> PersistedProductEvaluation? {
        let cacheID = PersistedProductEvaluation.candidateCacheID(ownerID: ownerID, candidateID: candidateID)
        let descriptor = FetchDescriptor<PersistedProductEvaluation>(
            predicate: #Predicate { $0.cacheID == cacheID && $0.ownerID == ownerID }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func ownerRows(ownerID: UUID) throws -> [PersistedProductEvaluation] {
        let descriptor = FetchDescriptor<PersistedProductEvaluation>(
            predicate: #Predicate { $0.ownerID == ownerID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func decision(
        from row: PersistedProductEvaluation,
        candidateRow: PersistedProductEvaluation?,
        evaluationData: Data
    ) throws -> ProductDecisionSnapshot {
        let evaluation = try JSONDecoder().decode(ProductEvaluation.self, from: evaluationData)
        guard evaluation.userID == row.ownerID, evaluation.productCandidateID == row.candidateID else {
            throw AstraError.server("A saved product decision couldn't be read.")
        }
        let candidateData = candidateRow?.encodedCandidate ?? row.encodedCandidate
        let candidate = try candidateData.map { try JSONDecoder().decode(ProductCandidate.self, from: $0) }
        guard candidate?.id == nil || candidate?.id == row.candidateID else {
            throw AstraError.server("A saved product couldn't be read.")
        }
        return ProductDecisionSnapshot(candidate: candidate, evaluation: evaluation)
    }

    private func prune(ownerID: UUID) throws {
        let rows = try ownerRows(ownerID: ownerID)
        let evaluations = rows.filter { $0.encodedEvaluation != nil }
            .sorted { ($0.evaluatedAt ?? .distantPast) > ($1.evaluatedAt ?? .distantPast) }
        for stale in evaluations.dropFirst(maximumRecentEvaluationRows) { modelContext.delete(stale) }
        let candidates = try ownerRows(ownerID: ownerID).filter { $0.encodedEvaluation == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
        for stale in candidates.dropFirst(maximumCandidateRows) { modelContext.delete(stale) }
        try modelContext.save()
    }
}
