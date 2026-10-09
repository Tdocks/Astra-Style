import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Makes a bounded, orientation-correct image rendition before closet bytes
/// enter Storage. JPEG remains JPEG; transparent PNG cutouts remain PNG.
enum ClosetImageThumbnailer {
    static let maxPixelSize = 660 // 220pt grid tile at the supported 3x scale.
    static let jpegQuality = 0.78

    static func thumbnailData(from data: Data) throws -> Data {
        let format = try CapturedImageUploadFormat.detect(data)
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
              ] as CFDictionary) else {
            throw AstraError.validation("That photo could not be prepared for your closet.")
        }

        let destinationType: CFString
        let options: [CFString: Any]
        switch format {
        case .jpeg:
            destinationType = UTType.jpeg.identifier as CFString
            options = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        case .png:
            destinationType = UTType.png.identifier as CFString
            options = [:]
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, destinationType, 1, nil) else {
            throw AstraError.server("That closet thumbnail could not be encoded.")
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination), !output.isEmpty else {
            throw AstraError.server("That closet thumbnail could not be encoded.")
        }
        return output as Data
    }
}
