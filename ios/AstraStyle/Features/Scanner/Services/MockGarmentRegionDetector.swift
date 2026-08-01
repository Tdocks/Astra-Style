//
//  MockGarmentRegionDetector.swift
//  AstraStyle
//
//  Injectable `GarmentRegionDetecting` for unit tests. Never touches Vision —
//  the live adapter (`LiveVisionGarmentRegionDetector`) is the untestable
//  half that this seam exists to isolate (see `CaptureQuality.swift`).
//

import CoreGraphics
import Foundation

public struct MockGarmentRegionDetectorError: Error, Sendable, Equatable {
    public init() {}
}

public struct MockGarmentRegionDetector: GarmentRegionDetecting, Sendable {
    public var region: GarmentRegion?
    public var error: MockGarmentRegionDetectorError?

    public init(region: GarmentRegion? = nil, error: MockGarmentRegionDetectorError? = nil) {
        self.region = region
        self.error = error
    }

    public func detectGarmentRegion(in image: CGImage) throws -> GarmentRegion? {
        _ = image
        if let error { throw error }
        return region
    }
}
