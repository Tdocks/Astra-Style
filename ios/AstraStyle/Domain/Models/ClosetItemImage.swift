//
//  ClosetItemImage.swift
//  AstraStyle
//
//  Maps `closet_item_images` (spec §9). Produced by the scanner pipeline
//  (spec §12): device-side capture plus server-side background removal and
//  analysis.
//

import Foundation

public struct ClosetItemImage: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var closetItemID: UUID
    public var imageType: ClosetImageType
    public var storagePath: String
    public var backgroundRemovedPath: String?
    public var isPrimary: Bool

    /// Free-form server analysis output (detected category confidence,
    /// OCR'd label text, dominant colors, etc). Intentionally untyped —
    /// see `AstraJSONValue` doc comment.
    public var analysisMetadata: AstraJSONValue?

    public init(
        id: UUID,
        closetItemID: UUID,
        imageType: ClosetImageType,
        storagePath: String,
        backgroundRemovedPath: String? = nil,
        isPrimary: Bool = false,
        analysisMetadata: AstraJSONValue? = nil
    ) {
        self.id = id
        self.closetItemID = closetItemID
        self.imageType = imageType
        self.storagePath = storagePath
        self.backgroundRemovedPath = backgroundRemovedPath
        self.isPrimary = isPrimary
        self.analysisMetadata = analysisMetadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case closetItemID = "closet_item_id"
        case imageType = "image_type"
        case storagePath = "storage_path"
        case backgroundRemovedPath = "background_removed_path"
        case isPrimary = "is_primary"
        case analysisMetadata = "analysis_metadata"
    }

    /// The path to render in grids/detail — prefers the background-removed
    /// cutout per spec §6.15 "Normalized cutout image", falling back to the
    /// raw capture.
    public var displayStoragePath: String {
        backgroundRemovedPath ?? storagePath
    }
}
