import Foundation
import SwiftData

/// Last confirmed product decision per owner/candidate. This is only a
/// presentation snapshot for history/offline reading; evaluateProduct always
/// asks the server for a fresh wardrobe score.
@Model
public final class PersistedProductEvaluation {
    @Attribute(.unique) public var cacheID: String
    public var ownerID: UUID
    public var candidateID: UUID
    public var evaluatedAt: Date?
    public var updatedAt: Date
    public var encodedEvaluation: Data?
    public var encodedCandidate: Data?

    public init(
        ownerID: UUID,
        candidateID: UUID,
        updatedAt: Date = .now,
        evaluatedAt: Date? = nil,
        encodedEvaluation: Data? = nil,
        encodedCandidate: Data? = nil,
        cacheID: String? = nil
    ) {
        self.cacheID = cacheID ?? Self.candidateCacheID(ownerID: ownerID, candidateID: candidateID)
        self.ownerID = ownerID
        self.candidateID = candidateID
        self.updatedAt = updatedAt
        self.evaluatedAt = evaluatedAt
        self.encodedEvaluation = encodedEvaluation
        self.encodedCandidate = encodedCandidate
    }

    public static func candidateCacheID(ownerID: UUID, candidateID: UUID) -> String {
        "\(ownerID.uuidString.lowercased()):\(candidateID.uuidString.lowercased()):candidate"
    }
}
