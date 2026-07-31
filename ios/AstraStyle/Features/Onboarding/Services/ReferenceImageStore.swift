//
//  ReferenceImageStore.swift
//  AstraStyle
//
//  Local, on-device holding place for the §5.1 step 11 reference photo,
//  between the moment the user chooses it and the moment onboarding is
//  submitted.
//
//  WHY THE IMAGE IS NOT IN THE DRAFT. `OnboardingDraft` is re-encoded and
//  written to disk on every mutation of any field, on every step. A JPEG
//  carried inside it would be base64'd and rewritten each time the user typed
//  a character into a later screen — megabytes of disk churn for a value that
//  never changes — and would land the photo inside a JSON file that the draft
//  store's own header describes as scratch state. The draft holds a filename;
//  the bytes live here.
//
//  WHY IT EXISTS AT ALL, RATHER THAN KEEPING THE BYTES IN MEMORY. Onboarding
//  is resumable by design (`P2-ONBOARD-11`): a force-quit two screens later
//  must not silently discard a photograph the user deliberately chose and
//  consented to. In-memory-only would lose it with no message, which is the
//  worst way to lose something a man was careful about.
//
//  WHY IT IS SEPARATE FROM SUPABASE STORAGE. ADR 0011: a guest never touches
//  Supabase, so for a guest this store is not a staging area, it is the final
//  destination. The same type therefore serves both "pending upload" and
//  "the only copy there will ever be", which is why nothing here knows what a
//  bucket is.
//
//  PROTECTION. Files are written with `.completeFileProtection` and excluded
//  from backup. A photograph of the user's face is the most sensitive thing
//  this app puts on disk, and the default protection class would leave it
//  readable while the device is locked.
//

import Foundation
import OSLog

/// Storage for the single optional reference image collected during
/// onboarding. Async because the file implementation does disk I/O; `Sendable`
/// because it crosses from the main-actor view model into a background write.
public protocol ReferenceImageStoring: Sendable {
    /// Writes `data` and returns the filename to record on the draft.
    /// Replaces whatever was stored before — there is exactly one reference
    /// image in this flow, so a second capture supersedes the first rather
    /// than accumulating.
    func save(_ data: Data) async -> String?
    func load(filename: String) async -> Data?
    func remove(filename: String) async
    /// Deletes everything this store holds. Called when the draft is cleared.
    func clear() async
}

public actor FileReferenceImageStore: ReferenceImageStoring {
    private let directory: URL
    private let logger = Logger(subsystem: "com.astrastyle.app", category: "onboarding")

    /// - Parameter userScope: Mirrors `FileOnboardingDraftStore`'s scoping for
    ///   the same reason and with more at stake: two people sharing a phone
    ///   must never be able to reach each other's photograph, and the cost of
    ///   preventing it is one path component.
    public init(userScope: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        let safe = userScope.replacingOccurrences(
            of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression
        )
        directory = base
            .appendingPathComponent("OnboardingReference", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func save(_ data: Data) async -> String? {
        await clear()
        let filename = "\(UUID().uuidString.lowercased()).jpg"
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var resourceURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? resourceURL.setResourceValues(values)
            return filename
        } catch {
            // Returning nil rather than throwing: the caller's only sane
            // response is "the photo did not stick", and the step is optional,
            // so this must not become an error the user has to dismiss before
            // he can carry on.
            logger.error("Failed to store reference image: \(error.localizedDescription)")
            return nil
        }
    }

    public func load(filename: String) async -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(filename))
    }

    public func remove(filename: String) async {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }

    public func clear() async {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// In-memory store for previews and tests.
public actor InMemoryReferenceImageStore: ReferenceImageStoring {
    private var files: [String: Data] = [:]

    public init() {}

    public func save(_ data: Data) async -> String? {
        files.removeAll()
        let filename = "\(UUID().uuidString.lowercased()).jpg"
        files[filename] = data
        return filename
    }

    public func load(filename: String) async -> Data? { files[filename] }
    public func remove(filename: String) async { files[filename] = nil }
    public func clear() async { files.removeAll() }
}
