//
//  ReferenceCameraPicker.swift
//  AstraStyle
//
//  A camera sheet for §5.1 step 11's "take one now", wrapping
//  `UIImagePickerController`.
//
//  WHY UIKIT AT ALL, IN A SWIFTUI APP. SwiftUI has no camera view. The
//  alternatives are this (about sixty lines, system-provided shutter, review
//  and retake, and the system's own permission prompt) or an `AVCaptureSession`
//  built by hand, which is the right answer for the closet scanner — that
//  screen needs a live preview with framing guidance, exposure feedback and
//  segmentation (`P3-SCAN-01`/`P3-SCAN-02`), none of which
//  `UIImagePickerController` will give it. This screen needs one photograph.
//  Building a capture pipeline here would mean two of them in the app, and the
//  one written first, for the simpler job, is the one that would get copied.
//
//  WHY THE AVAILABILITY CHECK IS PUBLISHED. Simulators have no camera, and
//  neither do a small number of real configurations. `isSourceTypeAvailable`
//  is the only reliable answer, and the caller uses it to decide whether the
//  button exists at all — spec §22's "no dead buttons" means not offering a
//  control that cannot work, rather than offering one that apologises.
//
//  NOTE ON COVERAGE: this path cannot be exercised on a simulator. The button
//  that presents it is correctly absent there, so the UI tests cover the
//  library path and the consent gate, and this file's behaviour on a device
//  is unverified by automation.
//

import SwiftUI
import UIKit

struct ReferenceCameraPicker: UIViewControllerRepresentable {
    /// Whether this device can actually take a photograph.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        // Guarded rather than assumed: `sourceType` silently falls back to the
        // photo library if the camera is unavailable, which would turn "Take
        // one now" into a second, differently-labelled library picker.
        if Self.isAvailable {
            controller.sourceType = .camera
            controller.cameraDevice = .front
        }
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    /// `@MainActor` because `UIImagePickerControllerDelegate` is main-actor
    /// isolated in the iOS 18+ SDK; without it this does not compile under
    /// Swift 6 strict concurrency rather than merely warning.
    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Data) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // JPEG here only to hand the caller `Data`; it is re-encoded and
            // downscaled by `ReferenceImagePreparation` before it is stored.
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 1) else {
                onCancel()
                return
            }
            onCapture(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
