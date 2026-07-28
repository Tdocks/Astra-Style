//
//  KyraThread.swift
//  AstraStyle
//
//  Maps `kyra_threads` (spec §9).
//

import Foundation

public struct KyraThread: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var userID: UUID
    public var title: String?
    public var lastMessageAt: Date?

    public init(id: UUID, userID: UUID, title: String? = nil, lastMessageAt: Date? = nil) {
        self.id = id
        self.userID = userID
        self.title = title
        self.lastMessageAt = lastMessageAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case lastMessageAt = "last_message_at"
    }
}
