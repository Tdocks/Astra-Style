//
//  StyleMemory.swift
//  AstraStyle
//
//  Maps `style_memories` (spec §9). Users can inspect and delete these
//  (spec §6.20, §29 "Delete individual reference and generated images" and
//  "View or delete stored style memories", spec §30 item 13).
//

import Foundation

public struct StyleMemory: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var userID: UUID
    public var memoryType: StyleMemoryType
    public var content: String
    public var confidence: Double
    public var sourceMessageID: UUID?

    /// When `false`, the memory still informs Kyra's reasoning but is
    /// withheld from the user-facing memory inspector — reserved for
    /// low-confidence signals not yet worth surfacing.
    public var isUserVisible: Bool

    public var embedding: [Float]?
    public var createdAt: Date

    public init(
        id: UUID,
        userID: UUID,
        memoryType: StyleMemoryType,
        content: String,
        confidence: Double,
        sourceMessageID: UUID? = nil,
        isUserVisible: Bool = true,
        embedding: [Float]? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.memoryType = memoryType
        self.content = content
        self.confidence = confidence
        self.sourceMessageID = sourceMessageID
        self.isUserVisible = isUserVisible
        self.embedding = embedding
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case memoryType = "memory_type"
        case content
        case confidence
        case sourceMessageID = "source_message_id"
        case isUserVisible = "is_user_visible"
        case embedding
        case createdAt = "created_at"
    }
}
