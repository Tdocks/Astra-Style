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

    /// The path to render when the closet is showing cut-outs.
    ///
    /// Kept as the no-argument property because it is what §6.15 describes —
    /// "Normalized cutout image" is the intended rendering, and the raw
    /// capture is the fallback. `displayStoragePath(preferringCutout:)` is
    /// for the surfaces that let the user say otherwise.
    /// Cut-out or capture, as the user has asked for.
    ///
    /// The toggle behind this gates DISPLAY, not production: the cut-out is
    /// made and stored whichever way the switch is set, so turning it on is
    /// instant rather than a re-scan of the whole wardrobe, and turning it
    /// off never destroys anything. On-device background removal is good but
    /// not universal — a garment shot against a busy background can come out
    /// with a bitten edge — and the setting is how a man says "that one
    /// looked better as a photograph" without losing the option.
    public func displayStoragePath(preferringCutout: Bool) -> String {
        preferringCutout ? displayStoragePath : storagePath
    }

    public var displayStoragePath: String {
        backgroundRemovedPath ?? storagePath
    }
}
