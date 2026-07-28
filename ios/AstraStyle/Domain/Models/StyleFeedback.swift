//
//  StyleFeedback.swift
//  AstraStyle
//
//  Maps `style_feedback` (spec §9). Every like/dislike/wear/skip signal
//  feeds the compatibility scorer's "historical co-wear/feedback" term
//  (spec §10, 10% weight).
//

import Foundation

public struct StyleFeedback: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var userID: UUID
    public var targetType: StyleFeedbackTargetType
    public var targetID: UUID
    public var signal: StyleFeedbackSignal
    public var reasonTags: [String]

    /// Optional free text. Per spec §18 analytics privacy guard, this field
    /// must never be forwarded to analytics events.
    public var freeText: String?

    public var createdAt: Date

    public init(
        id: UUID,
        userID: UUID,
        targetType: StyleFeedbackTargetType,
        targetID: UUID,
        signal: StyleFeedbackSignal,
        reasonTags: [String] = [],
        freeText: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.targetType = targetType
        self.targetID = targetID
        self.signal = signal
        self.reasonTags = reasonTags
        self.freeText = freeText
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case targetType = "target_type"
        case targetID = "target_id"
        case signal
        case reasonTags = "reason_tags"
        case freeText = "free_text"
        case createdAt = "created_at"
    }
}
