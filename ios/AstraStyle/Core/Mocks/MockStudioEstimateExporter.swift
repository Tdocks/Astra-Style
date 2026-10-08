import Foundation
import UIKit

/// A labeled synthetic image for previews and UI acceptance, never network.
@MainActor
public final class MockStudioEstimateExporter: StudioEstimateExporting {
    public init() {}
    public func export(imageURL: URL) async throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600), format: format).pngData { context in
            UIColor.lightGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
            ("Preview fixture" as NSString).draw(at: CGPoint(x: 24, y: 24), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        guard let response = HTTPURLResponse(url: imageURL, statusCode: 200, httpVersion: nil,
                                            headerFields: ["Content-Type": "image/png"]) else {
            throw AstraError.network("Couldn't prepare this preview fixture.")
        }
        return try await LiveStudioEstimateExporter { _ in (data, response) }.export(imageURL: imageURL)
    }
}
