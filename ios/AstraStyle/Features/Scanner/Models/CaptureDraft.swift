//
//  CaptureDraft.swift
//  AstraStyle
//
//  In-memory handoff between capture and review. `ScannerRoute.review`
//  carries only a UUID (Hashable); the prepared JPEG and analysis live here
//  so the route never stuffs megabytes into the navigation value.
//

import Foundation

public struct CaptureDraft: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var prepared: CapturePreparation.Prepared
    public var storagePath: String?
    public var signedPreviewURL: URL?
    public var analysis: ClosetItemAnalysisResult?

    public init(
        id: UUID = UUID(),
        prepared: CapturePreparation.Prepared,
        storagePath: String? = nil,
        signedPreviewURL: URL? = nil,
        analysis: ClosetItemAnalysisResult? = nil
    ) {
        self.id = id
        self.prepared = prepared
        self.storagePath = storagePath
        self.signedPreviewURL = signedPreviewURL
        self.analysis = analysis
    }
}
