import Foundation
import SwiftData

public struct MonthlyReviewSummary: Codable, Equatable, Sendable {
    public let ownerID: UUID
    public let monthKey: String
    public let dataRevision: String
    public let message: String
    public let threadID: UUID
    public let savedAt: Date

    public init(ownerID: UUID, monthKey: String, dataRevision: String, message: String, threadID: UUID, savedAt: Date = .now) {
        self.ownerID = ownerID
        self.monthKey = monthKey
        self.dataRevision = dataRevision
        self.message = message
        self.threadID = threadID
        self.savedAt = savedAt
    }
}

public protocol MonthlyReviewSummaryCaching: Sendable {
    func cached(ownerID: UUID, monthKey: String, dataRevision: String) async throws -> MonthlyReviewSummary?
    func store(_ summary: MonthlyReviewSummary) async throws
    func removeAll(ownerID: UUID) async throws
}

@Model
public final class PersistedMonthlyReviewSummary {
    @Attribute(.unique) public var cacheID: String
    public var ownerID: UUID
    public var monthKey: String
    public var dataRevision: String
    public var encodedSummary: Data
    public var savedAt: Date

    public init(summary: MonthlyReviewSummary) throws {
        cacheID = Self.cacheID(ownerID: summary.ownerID, monthKey: summary.monthKey, dataRevision: summary.dataRevision)
        ownerID = summary.ownerID
        monthKey = summary.monthKey
        dataRevision = summary.dataRevision
        encodedSummary = try JSONEncoder.astraDefault.encode(summary)
        savedAt = summary.savedAt
    }

    public static func cacheID(ownerID: UUID, monthKey: String, dataRevision: String) -> String {
        "\(ownerID.uuidString.lowercased()):\(monthKey):\(dataRevision)"
    }
}

@ModelActor
public actor SwiftDataMonthlyReviewSummaryCache: MonthlyReviewSummaryCaching {
    private let maximumRowsPerOwner = 24

    public func cached(ownerID: UUID, monthKey: String, dataRevision: String) async throws -> MonthlyReviewSummary? {
        let key = PersistedMonthlyReviewSummary.cacheID(ownerID: ownerID, monthKey: monthKey, dataRevision: dataRevision)
        let descriptor = FetchDescriptor<PersistedMonthlyReviewSummary>(
            predicate: #Predicate { $0.ownerID == ownerID && $0.cacheID == key }
        )
        guard let row = try modelContext.fetch(descriptor).first else { return nil }
        let summary = try JSONDecoder.astraDefault.decode(MonthlyReviewSummary.self, from: row.encodedSummary)
        guard summary.ownerID == ownerID, summary.monthKey == monthKey, summary.dataRevision == dataRevision,
              !summary.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AstraError.server("A saved Monthly Review couldn't be read.")
        }
        return summary
    }

    public func store(_ summary: MonthlyReviewSummary) async throws {
        guard !summary.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AstraError.validation("A Monthly Review must include readable text.")
        }
        let key = PersistedMonthlyReviewSummary.cacheID(ownerID: summary.ownerID, monthKey: summary.monthKey, dataRevision: summary.dataRevision)
        let descriptor = FetchDescriptor<PersistedMonthlyReviewSummary>(predicate: #Predicate { $0.cacheID == key })
        let row: PersistedMonthlyReviewSummary
        if let existing = try modelContext.fetch(descriptor).first {
            row = existing
            row.encodedSummary = try JSONEncoder.astraDefault.encode(summary)
            row.savedAt = summary.savedAt
        } else {
            row = try PersistedMonthlyReviewSummary(summary: summary)
            modelContext.insert(row)
        }
        try modelContext.save()
        let ownerID = summary.ownerID
        let ownerRows = try modelContext.fetch(FetchDescriptor<PersistedMonthlyReviewSummary>(
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        ))
        for stale in ownerRows.dropFirst(maximumRowsPerOwner) { modelContext.delete(stale) }
        try modelContext.save()
    }

    public func removeAll(ownerID: UUID) async throws {
        let descriptor = FetchDescriptor<PersistedMonthlyReviewSummary>(predicate: #Predicate { $0.ownerID == ownerID })
        for row in try modelContext.fetch(descriptor) { modelContext.delete(row) }
        try modelContext.save()
    }
}

public actor InMemoryMonthlyReviewSummaryCache: MonthlyReviewSummaryCaching {
    private var summaries: [String: MonthlyReviewSummary] = [:]

    public init() {}

    public func cached(ownerID: UUID, monthKey: String, dataRevision: String) -> MonthlyReviewSummary? {
        summaries[PersistedMonthlyReviewSummary.cacheID(ownerID: ownerID, monthKey: monthKey, dataRevision: dataRevision)]
    }

    public func store(_ summary: MonthlyReviewSummary) {
        summaries[PersistedMonthlyReviewSummary.cacheID(ownerID: summary.ownerID, monthKey: summary.monthKey, dataRevision: summary.dataRevision)] = summary
    }

    public func removeAll(ownerID: UUID) {
        summaries = summaries.filter { $0.value.ownerID != ownerID }
    }
}
