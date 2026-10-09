import Foundation

public struct ClosetItemInsights: Decodable, Equatable, Sendable {
    public struct SimilarItem: Decodable, Equatable, Sendable {
        public let itemId: UUID
        public let similarity: Int
    }
    public struct Pairing: Decodable, Equatable, Sendable {
        public let itemId: UUID
        public let score: Int
        public let missingInputs: [String]
    }
    public let redundancyScore: Int
    public let similarItems: [SimilarItem]
    public let pairings: [Pairing]
    public let savedOutfitIds: [UUID]
    public let replacementReason: String?
    public let missingRedundancyInputs: [String]
}
