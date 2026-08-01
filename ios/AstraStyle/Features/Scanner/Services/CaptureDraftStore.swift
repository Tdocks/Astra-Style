//
//  CaptureDraftStore.swift
//  AstraStyle
//
//  Session-scoped store for scanner drafts. Owned by `AppContainer` so the
//  capture screen can put a draft and the review screen can look it up by
//  the UUID on `ScannerRoute.review(capturedImageID:)`.
//

import Foundation
import Observation

@MainActor
@Observable
public final class CaptureDraftStore {
    private var drafts: [UUID: CaptureDraft] = [:]

    public init() {}

    public func put(_ draft: CaptureDraft) {
        drafts[draft.id] = draft
    }

    public func draft(id: UUID) -> CaptureDraft? {
        drafts[id]
    }

    public func update(_ draft: CaptureDraft) {
        drafts[draft.id] = draft
    }

    public func remove(id: UUID) {
        drafts.removeValue(forKey: id)
    }

    public func removeAll() {
        drafts.removeAll()
    }
}
