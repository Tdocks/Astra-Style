import Foundation
import ImageIO
import UIKit

@MainActor
public final class LiveStudioEstimateExporter: StudioEstimateExporting {
    private let dataLoader: @Sendable (URL) async throws -> (Data, URLResponse)

    public init(dataLoader: @escaping @Sendable (URL) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(from: $0)
    }) {
        self.dataLoader = dataLoader
    }

    public func export(imageURL: URL) async throws -> URL {
        let (data, response) = try await dataLoader(imageURL)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.mimeType?.hasPrefix("image/") == true,
              data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              width * height <= 16_000_000,
              let image = UIImage(data: data) else {
            throw AstraError.network("Couldn't download this estimate. Try again.")
        }
        try Task.checkCancellation()

        // Export typography is proportional to image pixels, independent of
        // the app's Dynamic Type setting. Keep the disclosure legible at any
        // provider resolution without cropping or modifying the outfit.
        let imageSize = CGSize(width: width, height: height)
        let inset = imageSize.width * 0.025
        let font = UIFont.systemFont(ofSize: max(12, imageSize.width * 0.023), weight: .medium)
        let label = "Astra Style · AI visual estimate\nFit, colors and garment details may differ."
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let labelSize = (label as NSString).boundingRect(
            with: CGSize(width: imageSize.width - 2 * inset, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: attributes, context: nil
        ).size
        let footerHeight = ceil(labelSize.height) + 2 * inset
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: imageSize.width, height: imageSize.height + footerHeight), format: format
        )
        let png = renderer.pngData { context in
            image.draw(in: CGRect(origin: .zero, size: imageSize))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: imageSize.height, width: imageSize.width, height: footerHeight))
            (label as NSString).draw(
                in: CGRect(x: inset, y: imageSize.height + inset, width: imageSize.width - 2 * inset, height: ceil(labelSize.height)),
                withAttributes: attributes
            )
        }
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("AstraEstimateExports", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        // Expire previous export files. Original images stay in private Studio
        // storage and are never copied into a public bucket for sharing.
        let oldFiles = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        for file in oldFiles {
            if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modified < Date.now.addingTimeInterval(-86_400) {
                try? manager.removeItem(at: file)
            }
        }
        let output = directory.appendingPathComponent("Astra-visual-estimate-\(UUID().uuidString).png")
        try png.write(to: output, options: [.atomic, .completeFileProtection])
        var protectedOutput = output
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedOutput.setResourceValues(values)
        return output
    }
}
