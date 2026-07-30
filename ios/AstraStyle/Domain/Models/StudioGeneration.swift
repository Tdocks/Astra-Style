//
//  StudioGeneration.swift
//  AstraStyle
//
//  Maps `studio_generations` (spec §9). Backs the Style Studio generation
//  pipeline (spec §13) and status polling via `GET /studio/status/:id`
//  (spec §14).
//

import Foundation

public struct StudioGeneration: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var userID: UUID
    public var referenceImagePath: String
    public var outfitID: UUID?

    /// The structured garment list / pose / background / lighting prompt
    /// payload described in spec §13's prompt template. Untyped because the
    /// exact shape is owned by the generation provider abstraction and may
    /// vary by provider.
    public var promptPayload: AstraJSONValue?

    public var status: StudioGenerationStatus
    public var resultImagePath: String?
    public var provider: String?
    public var errorMessage: String?

    /// Soft-delete timestamp from the retention policy in
    /// `adr/0010-image-storage-and-retention.md`. `nil` means live.
    ///
    /// This is not cosmetic. Generations are images of the user's face, and
    /// deletion is the mechanism behind spec §29's erasure obligation. A model
    /// blind to `deleted_at` would keep listing and keep displaying a
    /// generation the server considers erased — which is the single worst
    /// place in this app to be wrong.
    public var deletedAt: Date?

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        userID: UUID,
        referenceImagePath: String,
        outfitID: UUID? = nil,
        promptPayload: AstraJSONValue? = nil,
        status: StudioGenerationStatus = .queued,
        resultImagePath: String? = nil,
        provider: String? = nil,
        errorMessage: String? = nil,
        deletedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.userID = userID
        self.referenceImagePath = referenceImagePath
        self.outfitID = outfitID
        self.promptPayload = promptPayload
        self.status = status
        self.resultImagePath = resultImagePath
        self.provider = provider
        self.errorMessage = errorMessage
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case referenceImagePath = "reference_image_path"
        case outfitID = "outfit_id"
        case promptPayload = "prompt_payload"
        case status
        case resultImagePath = "result_image_path"
        case provider
        case errorMessage = "error_message"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Whether the generation can be retried without consuming another
    /// quota credit (spec §21: "Studio failed: ... allow retry without
    /// consuming another credit when failure is provider-side").
    public var isRetryableWithoutCharge: Bool {
        status == .failed && errorMessage != nil
    }

    /// `true` when the retention policy has erased this generation. Callers
    /// must filter on this before displaying or re-downloading a result.
    public var isDeleted: Bool { deletedAt != nil }
}
