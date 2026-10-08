import Foundation

/// An explicitly saved, private collection of Studio visual estimates.
public struct StudioLookbook: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let userID: UUID
    public var name: String
    public let createdAt: Date

    public init(id: UUID, userID: UUID, name: String, createdAt: Date = .now) {
        self.id = id
        self.userID = userID
        self.name = name
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case userID = "user_id"
        case createdAt = "created_at"
    }

    public static func validatedName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.unicodeScalars.count <= 80 else {
            throw AstraError.validation("Name your collection using 1–80 characters.")
        }
        return value
    }
}
