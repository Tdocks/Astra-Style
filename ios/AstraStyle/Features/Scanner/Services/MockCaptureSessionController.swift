//
//  MockCaptureSessionController.swift
//  AstraStyle
//
//  In-memory `CaptureSessionControlling` for unit tests and SwiftUI
//  previews. Never touches AVFoundation — that is the whole point of the
//  protocol seam in `CaptureSessionControlling.swift`.
//

import Foundation
import UIKit

public final class MockCaptureSessionController: CaptureSessionControlling, @unchecked Sendable {
    public var isHardwareAvailable: Bool
    public var authorization: CaptureCameraAuthorization
    public var stillJPEG: Data
    public var planes: [LuminancePlane]
    public var captureShouldFail: Bool

    private let lock = NSLock()
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
        lock.lock()
        defer { lock.unlock() }
        return authorization
    }

    public func requestPermissionIfNeeded() async -> Bool {
        lock.lock()
        switch authorization {
        case .authorized:
            lock.unlock()
            return true
        case .denied:
            lock.unlock()
            return false
        case .notDetermined:
            authorization = .authorized
            lock.unlock()
            return true
        }
    }

    public func start() async throws {
        lock.lock()
        guard isHardwareAvailable else {
            lock.unlock()
            throw CaptureSessionError.hardwareUnavailable
        }
        guard authorization == .authorized else {
            lock.unlock()
            throw CaptureSessionError.notAuthorized
        }
        running = true
        let planesToEmit = planes
        let continuation = frameContinuation
        lock.unlock()

        // Emit on a detached task so the AsyncStream consumer (the view
        // model) can interleave quality updates with user actions in tests.
        Task.detached { [weak self] in
            for plane in planesToEmit {
                self?.lock.lock()
                let isRunning = self?.running ?? false
                self?.lock.unlock()
                guard isRunning else { return }
                continuation?.yield(plane)
            }
        }
    }

    public func stop() {
        lock.lock()
        running = false
        frameContinuation?.finish()
        frameContinuation = nil
        lock.unlock()
    }

    public func qualityFrames() -> AsyncStream<LuminancePlane> {
        AsyncStream { continuation in
            self.lock.lock()
            self.frameContinuation = continuation
            self.lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.frameContinuation = nil
                self?.lock.unlock()
            }
        }
    }

    public func captureStillJPEG() async throws -> Data {
        lock.lock()
        let fail = captureShouldFail
        let data = stillJPEG
        let isRunning = running
        let authorized = authorization == .authorized
        let available = isHardwareAvailable
        lock.unlock()

        guard available else { throw CaptureSessionError.hardwareUnavailable }
        guard authorized else { throw CaptureSessionError.notAuthorized }
        guard isRunning else { throw CaptureSessionError.notRunning }
        guard !fail, !data.isEmpty else { throw CaptureSessionError.captureFailed }
        return data
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
        lock.lock()
        let continuation = frameContinuation
        lock.unlock()
        continuation?.yield(plane)
    }
}
