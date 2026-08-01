//
//  LiveCaptureSessionController.swift
//  AstraStyle
//
//  AVFoundation adapter for `CaptureSessionControlling`. Deliberately thin:
//  configure session, copy Y-plane samples into a `LuminancePlane`, take a
//  still JPEG. Blur/exposure verdicts stay in `CaptureQuality` so they remain
//  unit-testable on the simulator (see that file's header).
//
//  `@unchecked Sendable` matches `LiveWeatherService`: AVCaptureSession and
//  its delegate callbacks are bound to a private serial queue we own, and
//  every cross-isolation value we publish (`LuminancePlane`, `Data`,
//  authorization enums) is already `Sendable`. The unchecked annotation is
//  the boundary, not a licence to pass `CVPixelBuffer` into the view model.
//

import AVFoundation
import CoreVideo
import Foundation
import UIKit

public final class LiveCaptureSessionController: NSObject, CaptureSessionControlling, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.astrastyle.scanner.capture")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()

    private let lock = NSLock()
    private var frameContinuation: AsyncStream<LuminancePlane>.Continuation?
    private var photoContinuation: CheckedContinuation<Data, Error>?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var lastFrameEmit: CFAbsoluteTime = 0

    /// Minimum interval between quality-frame yields. Evaluating every
    /// camera frame is wasted work — the guidance label cannot update faster
    /// than a human can read it, and Laplacian variance is not free.
    private let minimumFrameInterval: CFAbsoluteTime = 0.1

    public override init() {
        super.init()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
    }

    public var isHardwareAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    public func currentAuthorization() -> CaptureCameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    public func requestPermissionIfNeeded() async -> Bool {
        switch currentAuthorization() {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        }
    }

    public func start() async throws {
        guard isHardwareAvailable else { throw CaptureSessionError.hardwareUnavailable }
        guard await requestPermissionIfNeeded() else { throw CaptureSessionError.notAuthorized }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureIfNeeded()
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.lock.lock()
            self.frameContinuation?.finish()
            self.frameContinuation = nil
            if let photo = self.photoContinuation {
                self.photoContinuation = nil
                photo.resume(throwing: CaptureSessionError.captureFailed)
            }
            self.lock.unlock()
        }
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
        return try await withCheckedThrowingContinuation { continuation in
            self.sessionQueue.async {
                guard self.isConfigured, self.session.isRunning else {
                    continuation.resume(throwing: CaptureSessionError.notRunning)
                    return
                }

                self.lock.lock()
                if self.photoContinuation != nil {
                    self.lock.unlock()
                    continuation.resume(throwing: CaptureSessionError.captureFailed)
                    return
                }
                self.photoContinuation = continuation
                self.lock.unlock()

                // Prefer JPEG when the device offers it; otherwise take the
                // default settings and rely on fileDataRepresentation().
                if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                    let jpegSettings = AVCapturePhotoSettings(
                        format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
                    )
                    self.photoOutput.capturePhoto(with: jpegSettings, delegate: self)
                } else {
                    self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
                }
            }
        }
    }

    @MainActor
    public func installPreview(into host: UIView) {
        let layer: AVCaptureVideoPreviewLayer
        if let existing = previewLayer {
            layer = existing
        } else {
            layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            previewLayer = layer
        }
        layer.frame = host.bounds
        if layer.superlayer !== host.layer {
            host.layer.insertSublayer(layer, at: 0)
        }
    }

    @MainActor
    public func removePreview(from host: UIView) {
        guard let layer = previewLayer, layer.superlayer === host.layer else { return }
        layer.removeFromSuperlayer()
    }

    // MARK: - Configuration

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            throw CaptureSessionError.hardwareUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CaptureSessionError.hardwareUnavailable
        }
        session.addInput(input)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw CaptureSessionError.hardwareUnavailable
        }
        session.addOutput(videoOutput)

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            throw CaptureSessionError.hardwareUnavailable
        }
        session.addOutput(photoOutput)

        session.commitConfiguration()
        isConfigured = true
    }
}

// MARK: - Video frames → LuminancePlane

extension LiveCaptureSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let continuation = frameContinuation
        let elapsed = now - lastFrameEmit
        if elapsed < minimumFrameInterval {
            lock.unlock()
            return
        }
        lastFrameEmit = now
        lock.unlock()

        guard let continuation else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let plane = Self.luminancePlane(from: buffer) else { return }
        continuation.yield(plane)
    }

    /// Copies and downsamples the Y plane of a 420f/420v buffer into a
    /// `LuminancePlane` at `CaptureQuality.analysisLongestEdge`. Point-
    /// samples rather than area-averages — good enough for a live guidance
    /// throttle, and avoids pulling CoreGraphics onto the capture queue.
    nonisolated static func luminancePlane(from buffer: CVPixelBuffer) -> LuminancePlane? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        guard width > 0, height > 0, bytesPerRow > 0 else { return nil }

        let longestEdge = CaptureQuality.analysisLongestEdge
        let scale = min(1, Double(longestEdge) / Double(max(width, height)))
        let outWidth = max(1, Int((Double(width) * scale).rounded()))
        let outHeight = max(1, Int((Double(height) * scale).rounded()))

        var samples = [UInt8](repeating: 0, count: outWidth * outHeight)
        let source = base.assumingMemoryBound(to: UInt8.self)
        for row in 0..<outHeight {
            let sourceRow = min(height - 1, Int((Double(row) / Double(outHeight) * Double(height)).rounded(.down)))
            let sourceRowStart = sourceRow * bytesPerRow
            let destinationRowStart = row * outWidth
            for column in 0..<outWidth {
                let sourceColumn = min(
                    width - 1,
                    Int((Double(column) / Double(outWidth) * Double(width)).rounded(.down))
                )
                samples[destinationRowStart + column] = source[sourceRowStart + sourceColumn]
            }
        }
        return LuminancePlane(samples: samples, width: outWidth, height: outHeight)
    }
}

// MARK: - Still photo

extension LiveCaptureSessionController: AVCapturePhotoCaptureDelegate {
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        lock.lock()
        let continuation = photoContinuation
        photoContinuation = nil
        lock.unlock()

        guard let continuation else { return }

        if error != nil {
            continuation.resume(throwing: CaptureSessionError.captureFailed)
            return
        }
        guard let data = photo.fileDataRepresentation(), !data.isEmpty else {
            continuation.resume(throwing: CaptureSessionError.captureFailed)
            return
        }
        continuation.resume(returning: data)
    }
}
