//
//  ScannerCaptureViewModelTests.swift
//  AstraStyleTests
//
//  Unit coverage for the scanner capture state machine (P3-SCAN-01 /
//  P3-SCAN-06). The live AVFoundation adapter is never constructed here —
//  every path runs through `MockCaptureSessionController`.
//

import CoreGraphics
import Foundation
import Testing
@testable import AstraStyle

@Suite("ScannerCaptureViewModel")
@MainActor
struct ScannerCaptureViewModelTests {

    @Test("Without camera hardware, onAppear skips the permission prompt and lands in capturing with the shutter hidden")
    func unavailableHardwareIsImportOnly() async {
        let session = MockCaptureSessionController(
            isHardwareAvailable: false,
            authorization: .notDetermined
        )
        let model = ScannerCaptureViewModel(captureSession: session, autoCaptureEnabled: false)

        await model.onAppear()

        #expect(model.phase == .capturing)
        #expect(model.showsShutter == false)
        #expect(session.currentAuthorization() == .notDetermined)
    }

    @Test("Denied camera permission still reaches capturing so Import remains available, and the shutter stays hidden")
    func deniedPermissionHidesShutter() async {
        let session = MockCaptureSessionController(
            isHardwareAvailable: true,
            authorization: .denied
        )
        let model = ScannerCaptureViewModel(captureSession: session, autoCaptureEnabled: false)

        await model.onAppear()

        #expect(model.phase == .capturing)
        #expect(model.showsShutter == false)
        #expect(model.authorization == .denied)
    }

    @Test("An imported JPEG runs through CapturePreparation and lands in draftReady")
    func importPreparesDraft() async throws {
        let jpeg = try #require(fixtureJPEG())
        let session = MockCaptureSessionController(isHardwareAvailable: false)
        let model = ScannerCaptureViewModel(captureSession: session, autoCaptureEnabled: false)

        await model.onAppear()
        await model.importImageData(jpeg)

        guard case .draftReady(let prepared) = model.phase else {
            Issue.record("Expected draftReady after import, got \(model.phase)")
            return
        }
        #expect(prepared.byteCount > 0)
        #expect(prepared.pixelWidth > 0)
        #expect(prepared.pixelHeight > 0)
        #expect(prepared.sizeReductionFactor >= 1)
    }

    @Test("A still capture through the mock session prepares a draft and stops the session")
    func shutterPreparesDraft() async throws {
        let jpeg = try #require(fixtureJPEG())
        let session = MockCaptureSessionController(
            isHardwareAvailable: true,
            authorization: .authorized,
            stillJPEG: jpeg
        )
        let model = ScannerCaptureViewModel(captureSession: session, autoCaptureEnabled: false)

        await model.onAppear()
        #expect(model.showsShutter == true)

        await model.captureStill()

        guard case .draftReady = model.phase else {
            Issue.record("Expected draftReady after shutter, got \(model.phase)")
            return
        }
    }

    @Test("A blurred quality frame surfaces guidance copy naming the garment, not the person")
    func blurredFrameSetsGuidance() async throws {
        let plane = try #require(blurredPlane())
        let session = MockCaptureSessionController(
            isHardwareAvailable: true,
            authorization: .authorized,
            planes: [plane]
        )
        let model = ScannerCaptureViewModel(captureSession: session, autoCaptureEnabled: false)

        await model.onAppear()
        // Give the detached emitter a turn.
        try await Task.sleep(for: .milliseconds(50))

        #expect(model.latestVerdict?.primaryIssue == .blurred)
        let guidance = try #require(model.guidanceText)
        #expect(guidance.localizedCaseInsensitiveContains("garment"))
        #expect(!guidance.localizedCaseInsensitiveContains("you look"))
    }

    @Test("Undecodable import bytes surface a retryable validation failure, not a silent drop")
    func undecodableImportFailsVisibly() async {
        let session = MockCaptureSessionController(isHardwareAvailable: false)
        let model = ScannerCaptureViewModel(captureSession: session, autoCaptureEnabled: false)

        await model.onAppear()
        await model.importImageData(Data("not-an-image".utf8))

        guard case .failed(let error) = model.phase else {
            Issue.record("Expected failed phase for undecodable bytes, got \(model.phase)")
            return
        }
        #expect(error.category == .validation)
    }

    @Test("Retake returns from a draft to capturing")
    func retakeRestoresCapture() async throws {
        let jpeg = try #require(fixtureJPEG())
        let session = MockCaptureSessionController(isHardwareAvailable: false)
        let model = ScannerCaptureViewModel(captureSession: session, autoCaptureEnabled: false)

        await model.onAppear()
        await model.importImageData(jpeg)
        #expect({
            if case .draftReady = model.phase { return true }
            return false
        }())

        await model.retake()
        #expect(model.phase == .capturing)
    }
}

// MARK: - Fixtures

private func fixtureJPEG() -> Data? {
    guard let image = ScannerImageFixtures.checkerboard(width: 640, height: 480, cell: 16) else {
        return nil
    }
    return ScannerImageFixtures.jpegData(from: image, includeMetadata: false)
}

private func blurredPlane() -> LuminancePlane? {
    // A near-uniform mid-grey plane has almost no Laplacian energy — the
    // focus measure reports it as blurred when luminance is high enough
    // for the measurement to be meaningful.
    let width = 64
    let height = 64
    let samples = [UInt8](repeating: 140, count: width * height)
    return LuminancePlane(samples: samples, width: width, height: height)
}
