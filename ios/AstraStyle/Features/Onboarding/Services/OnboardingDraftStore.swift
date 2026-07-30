//
//  OnboardingDraftStore.swift
//  AstraStyle
//
//  Local persistence for the in-progress draft.
//
//  Onboarding is eight screens. Without this, a phone call at step six costs
//  the user every answer, and nobody fills in their inseam twice. The draft is
//  written after each step and cleared once the server has accepted it.
//
//  Stored on disk as JSON in Application Support rather than in UserDefaults:
//  the draft contains measurements and appearance details, and UserDefaults is
//  a plist that syncs and shows up in backups more readily than a file we
//  control the protection class of.
//
//  NOT the Keychain either, despite the sensitivity. The Keychain is for
//  secrets that must survive app deletion and be shared between processes; this
//  is a scratch value with a natural end of life, and putting it there would
//  mean a stale draft outliving an uninstall.
//

import Foundation
import OSLog

public protocol OnboardingDraftStoring: Sendable {
    func load() async -> OnboardingDraft?
    func save(_ draft: OnboardingDraft) async
    func clear() async
}

public actor FileOnboardingDraftStore: OnboardingDraftStoring {
    private let url: URL
    private let logger = Logger(subsystem: "com.astrastyle.app", category: "onboarding")

    /// - Parameter userScope: Included in the filename so a draft belonging to a
    ///   guest session is never handed to a different account on the same
    ///   device. Two people sharing a phone is unusual; silently importing one
    ///   man's measurements into another man's profile is unacceptable, and the
    ///   cost of preventing it is one path component.
    public init(userScope: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        let directory = base.appendingPathComponent("Onboarding", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = userScope.replacingOccurrences(
            of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression
        )
        url = directory.appendingPathComponent("draft-\(safe).json")
    }

    public func load() async -> OnboardingDraft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(OnboardingDraft.self, from: data)
        } catch {
            // A draft written by an older build whose shape has since changed
            // must not wedge the flow. Discard it and start clean: losing an
            // in-progress draft is a bad morning, being unable to onboard at all
            // is a lost user.
            logger.warning("Discarding undecodable onboarding draft: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    public func save(_ draft: OnboardingDraft) async {
        do {
            let data = try JSONEncoder().encode(draft)
            try data.write(to: url, options: [.atomic])
            // Excluded from iCloud/iTunes backup. The draft is device-local
            // scratch state, and measurements do not belong in a backup the
            // user did not ask to put them in.
            var resourceURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? resourceURL.setResourceValues(values)
        } catch {
            // A failed draft save must never block progress through the flow.
            // The user's answers are still in memory; losing the ability to
            // resume is strictly better than refusing to continue.
            logger.error("Failed to save onboarding draft: \(error.localizedDescription)")
        }
    }

    public func clear() async {
        try? FileManager.default.removeItem(at: url)
    }
}

/// In-memory store for previews and tests.
public actor InMemoryOnboardingDraftStore: OnboardingDraftStoring {
    private var draft: OnboardingDraft?
    public init(draft: OnboardingDraft? = nil) { self.draft = draft }
    public func load() async -> OnboardingDraft? { draft }
    public func save(_ draft: OnboardingDraft) async { self.draft = draft }
    public func clear() async { draft = nil }
}
