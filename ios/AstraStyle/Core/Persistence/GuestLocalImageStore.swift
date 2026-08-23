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
        let name = UUID().uuidString.lowercased() + ".jpg"
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
