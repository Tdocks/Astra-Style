//
//  MockCaptureSessionController.swift
//  AstraStyle
//
//  In-memory `CaptureSessionControlling` for unit tests and SwiftUI
//  previews. Never touches AVFoundation — that is the whole point of the
//  protocol seam in `CaptureSessionControlling.swift`.
//
//  No `NSLock`: Swift 6 marks `NSLock.lock` unavailable from `async`
//  contexts, and this mock is only driven from `@MainActor` tests/previews.
//  Frame emission is synchronous inside `start()` so nothing races a lock.
//

import Foundation
import UIKit

public final class MockCaptureSessionController: CaptureSessionControlling, @unchecked Sendable {
    public var isHardwareAvailable: Bool
    public var authorization: CaptureCameraAuthorization
    public var stillJPEG: Data
    public var planes: [LuminancePlane]
    public var captureShouldFail: Bool

    private var running = false
    private var frameContinuation: AsyncStream<LuminancePlane>.Continuation?

    public init(
        isHardwareAvailable: Bool = true,
        authorization: CaptureCameraAuthorization = .authorized,
        stillJPEG: Data = Data(),
        planes: [LuminancePlane] = [],
        captureShouldFail: Bool = false
    ) {
        self.isHardwareAvailable = isHardwareAvailable
        self.authorization = authorization
        self.stillJPEG = stillJPEG
        self.planes = planes
        self.captureShouldFail = captureShouldFail
    }

    public func currentAuthorization() -> CaptureCameraAuthorization {
        authorization
    }

    public func requestPermissionIfNeeded() async -> Bool {
        switch authorization {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            authorization = .authorized
            return true
        }
    }

    public func start() async throws {
        guard isHardwareAvailable else { throw CaptureSessionError.hardwareUnavailable }
        guard authorization == .authorized else { throw CaptureSessionError.notAuthorized }
        running = true

        // Yield any preloaded planes now that the view model has subscribed
        // via `qualityFrames()` (called before `start()` in the VM).
        if let continuation = frameContinuation {
            for plane in planes {
                continuation.yield(plane)
            }
        }
    }

    public func stop() {
        running = false
        frameContinuation?.finish()
        frameContinuation = nil
    }

    public func qualityFrames() -> AsyncStream<LuminancePlane> {
        AsyncStream { continuation in
            self.frameContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.frameContinuation = nil
            }
        }
    }

    public func captureStillJPEG() async throws -> Data {
        guard isHardwareAvailable else { throw CaptureSessionError.hardwareUnavailable }
        guard authorization == .authorized else { throw CaptureSessionError.notAuthorized }
        guard running else { throw CaptureSessionError.notRunning }
        guard !captureShouldFail, !stillJPEG.isEmpty else { throw CaptureSessionError.captureFailed }
        return stillJPEG
    }

    @MainActor
    public func installPreview(into host: UIView) {
        // No live camera in the mock — the capture screen draws its own
        // framing guide over the design-system background.
        _ = host
    }

    @MainActor
    public func removePreview(from host: UIView) {
        _ = host
    }

    /// Test helper: push one more plane while the session is running.
    public func emit(_ plane: LuminancePlane) {
        frameContinuation?.yield(plane)
    }
}
