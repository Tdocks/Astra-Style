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
    /// Device-side region / OCR / colour hints produced before review
    /// (P3-SCAN-06). Review prefers these over re-running Vision.
    public var deviceHints: GarmentDeviceHints?
    public var storagePath: String?
    public var signedPreviewURL: URL?
    public var analysis: ClosetItemAnalysisResult?

    public init(
        id: UUID = UUID(),
        prepared: CapturePreparation.Prepared,
        deviceHints: GarmentDeviceHints? = nil,
        storagePath: String? = nil,
        signedPreviewURL: URL? = nil,
        analysis: ClosetItemAnalysisResult? = nil
    ) {
        self.id = id
        self.prepared = prepared
        self.deviceHints = deviceHints
        self.storagePath = storagePath
        self.signedPreviewURL = signedPreviewURL
        self.analysis = analysis
    }
}
