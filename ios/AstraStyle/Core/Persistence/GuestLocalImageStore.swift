//
//  GuestLocalImageStore.swift
//  AstraStyle
//
//  On-device closet photos for anonymous sessions. ADR 0011: guest photo
//  bytes never reach `user-content`. Paths are `guest-local/{file}` and
//  resolve through the file URL, not Storage.
//

import Foundation

public enum GuestLocalImageStore: Sendable {
    public static let pathPrefix = "guest-local/"

    public static func isLocal(_ storagePath: String) -> Bool {
        storagePath.hasPrefix(pathPrefix)
    }

    public static func save(_ data: Data, userID: UUID) throws -> String {
        let directory = try directoryURL(userID: userID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let format = try CapturedImageUploadFormat.detect(data)
        let name = UUID().uuidString.lowercased() + "." + format.fileExtension
        let fileURL = directory.appendingPathComponent(name)
        try data.write(to: fileURL, options: .atomic)
        return pathPrefix + userID.uuidString.lowercased() + "/" + name
    }

    public static func fileURL(for storagePath: String) -> URL? {
        guard isLocal(storagePath) else { return nil }
        let relative = String(storagePath.dropFirst(pathPrefix.count))
        let parts = relative.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let userID = UUID(uuidString: parts[0]) else { return nil }
        return try? directoryURL(userID: userID).appendingPathComponent(parts[1])
    }

    public static func delete(_ storagePath: String) throws {
        guard let url = fileURL(for: storagePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Original image bytes for a local path, or `nil` if the file is gone.
    /// The legacy method name is retained for account-migration callers.
    public static func jpegData(for storagePath: String) -> Data? {
        guard let url = fileURL(for: storagePath) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func directoryURL(userID: UUID) throws -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AstraError.server("Couldn't store that photo on this device.")
        }
        return root
            .appendingPathComponent("AstraStyle", isDirectory: true)
            .appendingPathComponent("guest-images", isDirectory: true)
            .appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
    }
}

/// Prepared captures are JPEG; Vision foreground masks are transparent PNG.
/// Keep their actual format rather than labelling a cutout as JPEG.
enum CapturedImageUploadFormat {
    case jpeg
    case png

    var fileExtension: String { self == .png ? "png" : "jpg" }
    var contentType: String { self == .png ? "image/png" : "image/jpeg" }

    static func detect(_ data: Data) throws -> Self {
        if data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { return .png }
        if data.starts(with: [255, 216, 255]) { return .jpeg }
        throw AstraError.validation("That photo format isn't supported.")
    }
}
