//
//  CaptureSessionPreview.swift
//  AstraStyle
//
//  UIKit bridge that hosts the live `AVCaptureVideoPreviewLayer` installed
//  by `CaptureSessionControlling.installPreview(into:)`. The view model
//  never sees this type — only the capture screen does.
//

import SwiftUI
import UIKit

struct CaptureSessionPreview: UIViewRepresentable {
    let session: any CaptureSessionControlling

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        uiView.session = session
        session.installPreview(into: uiView)
        uiView.setNeedsLayout()
    }

    static func dismantleUIView(_ uiView: PreviewHostView, coordinator: ()) {
        uiView.session?.removePreview(from: uiView)
        uiView.session = nil
    }

    final class PreviewHostView: UIView {
        var session: (any CaptureSessionControlling)?

        override func layoutSubviews() {
            super.layoutSubviews()
            // Keep the preview layer matched to the host bounds after
            // rotation / sheet resize. The controller owns the layer; we
            // only ask it to reinstall so its frame tracks ours.
            if let session {
                session.installPreview(into: self)
                layer.sublayers?.first?.frame = bounds
            }
        }
    }
}
