//
//  KyraMessage.swift
//  AstraStyle
//
//  Maps `kyra_messages` (spec §9).
//

import Foundation

public struct KyraMessage: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var threadID: UUID
    public var role: KyraMessageRole
    public var content: String

    /// Present on `.kyra` role messages; mirrors spec §11's response
    /// schema. Absent on plain `.user` messages.
    public var structuredPayload: KyraStructuredResponse?

    /// Provider/model bookkeeping (latency, model name/version, token
    /// counts). Never surfaced to the user; intentionally untyped.
    public var modelMetadata: AstraJSONValue?

    public var createdAt: Date

    public init(
        id: UUID,
        threadID: UUID,
        role: KyraMessageRole,
        content: String,
        structuredPayload: KyraStructuredResponse? = nil,
        modelMetadata: AstraJSONValue? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.threadID = threadID
        self.role = role
        self.content = content
        self.structuredPayload = structuredPayload
        self.modelMetadata = modelMetadata
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case threadID = "thread_id"
        case role
        case content
        case structuredPayload = "structured_payload"
        case modelMetadata = "model_metadata"
        case createdAt = "created_at"
    }
}
