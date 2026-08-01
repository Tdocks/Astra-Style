//
//  PreparedCapture.swift
//  AstraStyle
//
//  What the capture screen hands forward once blur/prepare (and, for
//  P3-SCAN-06, device-side region/OCR/colour) have run. Kept as its own
//  value so `ScannerCaptureViewModel.Phase.draftReady` can carry hints
//  without stuffing megabytes into `ScannerRoute`.
//

import Foundation

public struct PreparedCapture: Sendable, Equatable {
    public var prepared: CapturePreparation.Prepared
    public var deviceHints: GarmentDeviceHints?

    public init(prepared: CapturePreparation.Prepared, deviceHints: GarmentDeviceHints? = nil) {
        self.prepared = prepared
        self.deviceHints = deviceHints
    }
}
