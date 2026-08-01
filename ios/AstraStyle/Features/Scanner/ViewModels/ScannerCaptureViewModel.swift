//
//  ScannerCaptureViewModel.swift
//  AstraStyle
//
//  Drives the single-item capture screen (spec §6.16 / P3-SCAN-01 +
//  P3-SCAN-06). Owns permission, live quality guidance, shutter, Photos
//  import, and the prepare-for-upload step. Stops before review and
//  analyze — those are P3-SCAN-09 / P3-SCAN-07 and must not be faked here
//  (spec §22: absent is honest).
//
//  Patterned on `HomeViewModel`: `@MainActor` `@Observable`, an explicit
//  phase enum, and zero networking. The capture controller is a protocol
//  so CI can drive the whole state machine with
//  `MockCaptureSessionController`.
//

import CoreGraphics
import Foundation
import ImageIO
import Observation

@MainActor
@Observable
public final class ScannerCaptureViewModel {

    public enum Phase: Equatable {
        /// Asking for camera permission or starting the session.
        case starting
        /// Live preview (or import-only when hardware/permission is absent).
        case capturing
        /// Preparing a still / import through `CapturePreparation`.
        case preparing
        /// Local draft ready — prepared JPEG plus optional device hints
        /// (region / OCR / colour) so review does not re-run Vision.
        case draftReady(PreparedCapture)
        case failed(AstraError)

        public static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.starting, .starting), (.capturing, .capturing), (.preparing, .preparing):
                true
            case (.draftReady(let left), .draftReady(let right)):
                left == right
            case (.failed(let left), .failed(let right)):
                left == right
            default:
                false
            }
        }
    }

    public private(set) var phase: Phase = .starting
    public private(set) var authorization: CaptureCameraAuthorization = .notDetermined
    public private(set) var latestVerdict: CaptureQualityVerdict?
    public private(set) var isCapturingStill = false
    public private(set) var autoCaptureEnabled: Bool

    /// Hardware present AND authorized — shutter may appear.
    public var showsShutter: Bool {
        captureSession.isHardwareAvailable && authorization == .authorized
    }

    /// Guidance copy for the live preview, `nil` when the frame is fine or
    /// we are not in the capturing phase.
    public var guidanceText: String? {
        guard case .capturing = phase else { return nil }
        return latestVerdict?.guidance
    }

    public var guidanceSeverity: CaptureQualitySeverity {
        latestVerdict?.severity ?? .acceptable
    }

    private let captureSession: any CaptureSessionControlling
    /// Still-image Vision seams for P3-SCAN-06. Optional so unit tests that
    /// only care about prepare can omit them; production injects live
    /// adapters from `ScannerDestinationView`.
    private let regionDetector: (any GarmentRegionDetecting)?
    private let textRecognizer: (any LabelTextRecognizing)?
    private var qualityTask: Task<Void, Never>?
    private var consecutiveAcceptableFrames = 0
    private var hasAutoCapturedThisSession = false

    /// Consecutive acceptable frames before optional auto-capture fires.
    /// At the live controller's 10 Hz throttle this is ~0.8s of a clean
    /// frame — long enough to be intentional, short enough to feel responsive.
    private let autoCaptureFrameThreshold = 8

    public init(
        captureSession: any CaptureSessionControlling,
        autoCaptureEnabled: Bool = true,
        regionDetector: (any GarmentRegionDetecting)? = nil,
        textRecognizer: (any LabelTextRecognizing)? = nil
    ) {
        self.captureSession = captureSession
        self.autoCaptureEnabled = autoCaptureEnabled
        self.regionDetector = regionDetector
        self.textRecognizer = textRecognizer
    }

    // MARK: - Lifecycle

    public func onAppear() async {
        authorization = captureSession.currentAuthorization()
        phase = .starting

        if !captureSession.isHardwareAvailable {
            // Simulator / no camera: skip the permission prompt entirely
            // and offer Photos import as the real path (P3-SCAN-06).
            phase = .capturing
            return
        }

        let granted = await captureSession.requestPermissionIfNeeded()
        authorization = captureSession.currentAuthorization()
        guard granted else {
            phase = .capturing
            return
        }

        do {
            // Subscribe before `start()` so mock/live frames emitted on
            // session start are not dropped on an unbuffered AsyncStream.
            let stream = captureSession.qualityFrames()
            startConsumingQualityFrames(stream)
            try await captureSession.start()
            phase = .capturing
        } catch {
            qualityTask?.cancel()
            qualityTask = nil
            phase = .failed(mapSessionError(error))
        }
    }

    public func onDisappear() {
        qualityTask?.cancel()
        qualityTask = nil
        captureSession.stop()
        consecutiveAcceptableFrames = 0
    }

    // MARK: - Capture / import

    public func captureStill() async {
        guard showsShutter, !isCapturingStill else { return }
        guard case .capturing = phase else { return }

        isCapturingStill = true
        phase = .preparing
        defer { isCapturingStill = false }

        do {
            let jpeg = try await captureSession.captureStillJPEG()
            let prepared = try CapturePreparation.prepareForUpload(jpeg)
            let ready = finishPreparation(prepared)
            AstraHaptics.success()
            phase = .draftReady(ready)
            captureSession.stop()
            qualityTask?.cancel()
            qualityTask = nil
        } catch let failure as CapturePreparation.Failure {
            phase = .failed(mapPreparationFailure(failure))
        } catch {
            phase = .failed(mapSessionError(error))
        }
    }

    /// PhotosUI import path (P3-SCAN-06): same blur / prepare / region /
    /// OCR / colour pipeline as the shutter before review. Permission is
    /// requested by the system picker itself when the user taps Import —
    /// never earlier (spec §7).
    public func importImageData(_ data: Data) async {
        guard !isCapturingStill else { return }
        phase = .preparing

        // Evaluate quality on the import so a visibly bad photo gets the
        // same guidance a live frame would — then still prepare it; the
        // review screen is where the user decides to keep or retake.
        if let image = cgImage(from: data), let verdict = CaptureQuality.evaluate(image) {
            latestVerdict = verdict
        }

        do {
            let prepared = try CapturePreparation.prepareForUpload(data)
            let ready = finishPreparation(prepared)
            AstraHaptics.success()
            phase = .draftReady(ready)
            captureSession.stop()
            qualityTask?.cancel()
            qualityTask = nil
        } catch let failure as CapturePreparation.Failure {
            phase = .failed(mapPreparationFailure(failure))
        } catch {
            phase = .failed(AstraError.validation(
                String(localized: "That photo could not be prepared. Try another one.",
                       comment: "Scanner import preparation failure")
            ))
        }
    }

    /// Runs device-side region / OCR / colour on the prepared still.
    /// Deliberately NOT on the ~10 Hz quality stream — Vision there is
    /// outside the capture budget (see CaptureQuality header).
    private func finishPreparation(_ prepared: CapturePreparation.Prepared) -> PreparedCapture {
        guard let image = cgImage(from: prepared.data) else {
            return PreparedCapture(prepared: prepared, deviceHints: nil)
        }
        let hints = DeviceHintsExtraction.extract(
            from: image,
            regionDetector: regionDetector,
            textRecognizer: textRecognizer
        )
        return PreparedCapture(prepared: prepared, deviceHints: hints)
    }

    public func retake() async {
        latestVerdict = nil
        consecutiveAcceptableFrames = 0
        hasAutoCapturedThisSession = false
        await onAppear()
    }

    public func clearFailureAndReturnToCapture() async {
        await retake()
    }

    // MARK: - Quality stream

    private func startConsumingQualityFrames(_ stream: AsyncStream<LuminancePlane>) {
        qualityTask?.cancel()
        qualityTask = Task { [weak self] in
            for await plane in stream {
                guard let self, !Task.isCancelled else { return }
                self.handleQualityFrame(plane)
            }
        }
    }

    private func handleQualityFrame(_ plane: LuminancePlane) {
        guard case .capturing = phase else { return }
        let verdict = CaptureQuality.evaluate(plane)
        latestVerdict = verdict

        guard autoCaptureEnabled, !hasAutoCapturedThisSession, showsShutter else { return }
        if verdict.allowsAutoCapture, verdict.severity == .acceptable {
            consecutiveAcceptableFrames += 1
            if consecutiveAcceptableFrames >= autoCaptureFrameThreshold {
                hasAutoCapturedThisSession = true
                Task { await captureStill() }
            }
        } else {
            consecutiveAcceptableFrames = 0
        }
    }

    // MARK: - Mapping

    private func mapSessionError(_ error: Error) -> AstraError {
        if let sessionError = error as? CaptureSessionError {
            switch sessionError {
            case .hardwareUnavailable:
                return AstraError.validation(String(localized: "This device has no camera available for scanning.",
                                                    comment: "Scanner hardware unavailable"))
            case .notAuthorized:
                return AstraError.auth(String(localized: "Camera access is off. Import a photo instead, or turn the camera on in Settings.",
                                              comment: "Scanner camera permission denied"))
            case .notRunning, .captureFailed:
                return AstraError.validation(String(localized: "The capture did not come through. Try again.",
                                                    comment: "Scanner still capture failed"))
            }
        }
        return AstraError.validation(String(localized: "The capture did not come through. Try again.",
                                            comment: "Scanner unexpected capture failure"))
    }

    private func mapPreparationFailure(_ failure: CapturePreparation.Failure) -> AstraError {
        switch failure {
        case .undecodableImage:
            return AstraError.validation(String(localized: "That file is not an image Kyra can catalog. Try a photo of the garment.",
                                                comment: "Scanner undecodable import"))
        case .resizeFailed, .encodingFailed, .invalidTargetSize:
            return AstraError.validation(String(localized: "That photo could not be prepared. Try another one.",
                                                comment: "Scanner preparation failure"))
        }
    }

    private func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
