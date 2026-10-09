import Foundation
import UIKit
import XCTest
@testable import AstraStyle

final class AstraRemoteImageLoaderTests: XCTestCase {
    @MainActor
    func testResolverProvidedFileURLLoadsThroughSharedImageDecoder() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: rendererFormat)
        let bytes = renderer.pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        try bytes.write(to: fileURL, options: .atomic)

        let image = await AstraRemoteImageLoader.load(url: fileURL, maxPixelSize: nil, scale: 1)

        XCTAssertEqual(image?.size, CGSize(width: 8, height: 8))
    }
}
