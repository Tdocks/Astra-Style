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
    /// Small owner-private display rendition. `nil` on legacy rows; closet
    /// grids do not substitute a remote original for a missing thumbnail.
    public var thumbnailStoragePath: String?
    /// PNG rendition of a transparent cutout, when a cutout is available.
    public var backgroundRemovedThumbnailPath: String?
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
        thumbnailStoragePath: String? = nil,
        backgroundRemovedThumbnailPath: String? = nil,
        isPrimary: Bool = false,
        analysisMetadata: AstraJSONValue? = nil
    ) {
        self.id = id
        self.closetItemID = closetItemID
        self.imageType = imageType
        self.storagePath = storagePath
        self.backgroundRemovedPath = backgroundRemovedPath
        self.thumbnailStoragePath = thumbnailStoragePath
        self.backgroundRemovedThumbnailPath = backgroundRemovedThumbnailPath
        self.isPrimary = isPrimary
        self.analysisMetadata = analysisMetadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case closetItemID = "closet_item_id"
        case imageType = "image_type"
        case storagePath = "storage_path"
        case backgroundRemovedPath = "background_removed_path"
        case thumbnailStoragePath = "thumbnail_storage_path"
        case backgroundRemovedThumbnailPath = "background_removed_thumbnail_path"
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

    /// The grid-size path, falling back to the existing source/cutout on
    /// legacy rows. `AstraRemoteImage` decodes that fallback at tile size.
    public func gridThumbnailStoragePath(preferringCutout: Bool) -> String? {
        if preferringCutout, let backgroundRemovedPath {
            return backgroundRemovedThumbnailPath ?? backgroundRemovedPath
        }
        return thumbnailStoragePath ?? storagePath
    }

    /// The full-size path to try once if a known thumbnail object is missing.
    /// Its URL is signed in the same batch but deliberately not prefetched.
    public func gridFallbackStoragePath(preferringCutout: Bool) -> String? {
        if preferringCutout, let backgroundRemovedPath {
            return backgroundRemovedThumbnailPath == nil ? nil : backgroundRemovedPath
        }
        return thumbnailStoragePath == nil ? nil : storagePath
    }
}

/// Derives the deterministic private-object sibling used for an image's
/// downsampled rendition. A UUID-based image stem and `.jpg`/`.png` format
/// are required so arbitrary paths cannot be converted into upload paths.
public enum ClosetImageVariantPaths {
    public static func thumbnail(for sourcePath: String) -> String? {
        guard let slash = sourcePath.lastIndex(of: "/"),
              let dot = sourcePath.lastIndex(of: "."), dot > slash else { return nil }
        let stem = String(sourcePath[sourcePath.index(after: slash)..<dot])
        let ext = String(sourcePath[sourcePath.index(after: dot)...])
        let uuidStem = stem.hasSuffix("-cutout") ? String(stem.dropLast("-cutout".count)) : stem
        guard UUID(uuidString: uuidStem) != nil, uuidStem == uuidStem.lowercased(),
              ext == "jpg" || ext == "png" else { return nil }
        return String(sourcePath[..<dot]) + ".thumb." + ext
    }
}
