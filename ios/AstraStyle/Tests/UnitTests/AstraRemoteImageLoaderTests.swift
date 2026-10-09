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

    func testMissingVariantFallsBackOnceToBoundedOriginalDecode() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1600), format: format)
        let originalBytes = renderer.pngData { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
        }
        let variantURL = try XCTUnwrap(URL(string: "https://example.invalid/item.thumb.jpg"))
        let originalURL = try XCTUnwrap(URL(string: "https://example.invalid/item.jpg"))
        let fetcher = StubImageFetcher(originalBytes: originalBytes)

        let image = await AstraRemoteImageLoader.load(
            url: variantURL,
            fallbackURL: originalURL,
            maxPixelSize: 220,
            scale: 3,
            fetchData: { url in await fetcher.fetch(url) }
        )

        XCTAssertNotNil(image)
        let paths = await fetcher.requestedPaths
        XCTAssertEqual(paths, [variantURL.path(), originalURL.path()])
        XCTAssertLessThanOrEqual(max(image?.cgImage?.width ?? 0, image?.cgImage?.height ?? 0), 660)
    }

    func testTransientVariantFailureDoesNotFetchOriginalFallback() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format)
        let originalBytes = renderer.pngData { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let variantURL = try XCTUnwrap(URL(string: "https://example.invalid/item.thumb.jpg"))
        let originalURL = try XCTUnwrap(URL(string: "https://example.invalid/item.jpg"))
        let fetcher = StubImageFetcher(originalBytes: originalBytes, variantStatus: 503)

        let image = await AstraRemoteImageLoader.load(
            url: variantURL,
            fallbackURL: originalURL,
            maxPixelSize: 220,
            scale: 3,
            fetchData: { url in await fetcher.fetch(url) }
        )

        XCTAssertNil(image)
        let paths = await fetcher.requestedPaths
        XCTAssertEqual(paths, [variantURL.path()])
    }

    private actor StubImageFetcher {
        private let originalBytes: Data
        private let variantStatus: Int
        private(set) var requestedPaths: [String] = []

        init(originalBytes: Data, variantStatus: Int = 400) {
            self.originalBytes = originalBytes
            self.variantStatus = variantStatus
        }

        func fetch(_ url: URL) -> AstraRemoteImageLoader.Response {
            requestedPaths.append(url.path())
            if url.path().contains(".thumb.") {
                let body = variantStatus == 404 || variantStatus == 400
                    ? Data(#"{"statusCode":"404","error":"not_found"}"#.utf8)
                    : Data(#"{"error":"temporarily_unavailable"}"#.utf8)
                return AstraRemoteImageLoader.Response(data: body, statusCode: variantStatus)
            }
            return AstraRemoteImageLoader.Response(data: originalBytes, statusCode: 200)
        }
    }
}
