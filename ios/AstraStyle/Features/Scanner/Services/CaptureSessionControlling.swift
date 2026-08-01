//
//  CaptureSessionControlling.swift
//  AstraStyle
//
//  The thin, untestable shell around AVFoundation for P3-SCAN-01.
//
//  CaptureQuality.swift's header is the design brief for this file: the
//  simulator has no camera, CI never will, and P3-SCAN-01's live-blur
//  criterion is a device-only human test. So the camera session may produce
//  frames and still JPEGs, and must do nothing else — every judgement about
//  a frame lives in `CaptureQuality` as a synchronous function over a
//  `Sendable` `LuminancePlane` a unit test can synthesise.
//
//  Protocol-first so `ScannerCaptureViewModel` can be exercised in CI with
//  `MockCaptureSessionController`. The live adapter is the only file that
//  imports AVFoundation.
//

import Foundation
import UIKit

/// Camera authorization as the capture screen needs to render it — three
/// states with three different UIs, not a Bool.
public enum CaptureCameraAuthorization: Sendable, Equatable {
    /// System has not asked yet. Entering the capture screen triggers the ask
    /// (spec §7 — camera only when scanning).
    case notDetermined
    /// User granted access; live preview may start.
    case authorized
    /// Denied or restricted. The shutter is absent (spec §22 — no dead
    /// buttons); Photos import remains available.
    case denied
}

/// Errors from the capture session itself, before any upload.
public enum CaptureSessionError: Error, Sendable, Equatable {
    case hardwareUnavailable
    case notAuthorized
    case notRunning
    case captureFailed
}

/// Produces live preview frames and still JPEGs for the scanner.
///
/// Implementations must keep quality judgement out of this type — yield
/// `LuminancePlane` values (or JPEG `Data`) and let `CaptureQuality` /
/// `CapturePreparation` decide what they mean.
public protocol CaptureSessionControlling: Sendable {
    /// `false` on the simulator and on devices with no rear camera. Callers
    /// hide the shutter rather than apologising after a tap.
    var isHardwareAvailable: Bool { get }

    func currentAuthorization() -> CaptureCameraAuthorization

    /// Requests camera permission only when the capture screen needs it
    /// (spec §7). Idempotent when already determined.
    func requestPermissionIfNeeded() async -> Bool

    /// Starts the session and begins yielding quality frames. Safe to call
    /// when already running.
    func start() async throws

    /// Stops the session and ends the quality-frame stream. Safe when idle.
    func stop()

    /// Stream of greyscale planes for `CaptureQuality.evaluate(_:)`. Ends
    /// when `stop()` is called or the session fails.
    func qualityFrames() -> AsyncStream<LuminancePlane>

    /// Captures one still as JPEG bytes (full resolution, device metadata
    /// intact). The caller runs `CapturePreparation.prepareForUpload`.
    func captureStillJPEG() async throws -> Data

    /// Installs a live preview layer into `host`. No-op when hardware is
    /// unavailable. Main-actor only — `UIView` is main-actor isolated.
    @MainActor
    func installPreview(into host: UIView)

    /// Removes any preview layer previously installed into `host`.
    @MainActor
    func removePreview(from host: UIView)
}
