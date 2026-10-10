import SwiftUI
import XCTest
@testable import AstraStyle

@MainActor
final class MajorScreenSnapshotTests: XCTestCase {
    private let screenSize = CGSize(width: 393, height: 852)
    private var isRecording: Bool {
        FileManager.default.fileExists(atPath: Self.recordMarkerURL.path)
    }

    func testMajorScreensAgainstCommittedSnapshots() async throws {
        for screen in MajorSnapshotScreen.allCases {
            for state in [MajorSnapshotState.populated, .empty] {
                for appearance in [ColorScheme.light, .dark] {
                    let sizes = state == .populated
                        ? [DynamicTypeSize.large, .accessibility3, .accessibility5]
                        : [.large]
                    for dynamicTypeSize in sizes {
                        let view = try await MajorSnapshotFixture.make(screen: screen, state: state)
                        let image = try await render(
                            view,
                            appearance: appearance,
                            dynamicTypeSize: dynamicTypeSize
                        )
                        try assertSnapshot(
                            image,
                            name: snapshotName(screen, state, appearance, dynamicTypeSize)
                        )
                    }
                }
            }
        }
    }

    func testPixelComparatorDetectsAChangedPixel() throws {
        let original = solidImage(color: .black)
        let same = solidImage(color: .black)
        let changed = solidImage(color: .black, changedPixel: true)

        XCTAssertNoThrow(try VisualSnapshotComparator.assertMatches(original, expected: same))
        XCTAssertThrowsError(try VisualSnapshotComparator.assertMatches(changed, expected: original))
    }

    func testPixelComparatorRejectsDifferentBackingPixelDimensions() throws {
        let onePixelPerPoint = solidImage(color: .black, scale: 1)
        let twoPixelsPerPoint = solidImage(color: .black, scale: 2)

        XCTAssertEqual(onePixelPerPoint.size, twoPixelsPerPoint.size)
        XCTAssertNotEqual(onePixelPerPoint.cgImage?.width, twoPixelsPerPoint.cgImage?.width)
        XCTAssertThrowsError(
            try VisualSnapshotComparator.assertMatches(onePixelPerPoint, expected: twoPixelsPerPoint)
        )
    }

    private func render(
        _ view: AnyView,
        appearance: ColorScheme,
        dynamicTypeSize: DynamicTypeSize
    ) async throws -> UIImage {
        let bounds = CGRect(origin: .zero, size: screenSize)
        let root = view
            .frame(width: screenSize.width, height: screenSize.height)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.calendar, Calendar(identifier: .gregorian))
            .environment(\.timeZone, SnapshotClock.timeZone)
            .preferredColorScheme(appearance)
        let hostingController = UIHostingController(rootView: root)
        let window = UIWindow(frame: bounds)
        window.overrideUserInterfaceStyle = appearance == .dark ? .dark : .light
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = bounds
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var renderedImage: UIImage?
        UIView.performWithoutAnimation {
            renderedImage = UIGraphicsImageRenderer(size: screenSize, format: format).image { context in
                hostingController.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
                context.cgContext.flush()
            }
        }
        window.isHidden = true
        window.rootViewController = nil
        return try XCTUnwrap(renderedImage, "The snapshot view did not render.")
    }

    private func assertSnapshot(_ image: UIImage, name: String) throws {
        let fileURL = Self.baselineDirectory.appendingPathComponent("\(name).png")
        if isRecording {
            try FileManager.default.createDirectory(
                at: Self.baselineDirectory,
                withIntermediateDirectories: true
            )
            guard let data = image.pngData() else {
                XCTFail("Could not encode snapshot \(name).")
                return
            }
            try data.write(to: fileURL, options: .atomic)
            return
        }

        guard let bundleURL = Bundle(for: Self.self).url(
            forResource: name,
            withExtension: "png",
            subdirectory: "SnapshotBaselines"
        ), let expected = UIImage(contentsOfFile: bundleURL.path) else {
            XCTFail("Missing committed snapshot \(name).png. Create \(Self.recordMarkerURL.path) locally, rerun this test, inspect the PNG diff, then remove the marker and commit the reviewed baseline.")
            return
        }

        do {
            try VisualSnapshotComparator.assertMatches(image, expected: expected)
        } catch {
            let actualAttachment = XCTAttachment(image: image)
            actualAttachment.name = "\(name)-actual"
            actualAttachment.lifetime = .keepAlways
            add(actualAttachment)
            let expectedAttachment = XCTAttachment(image: expected)
            expectedAttachment.name = "\(name)-expected"
            expectedAttachment.lifetime = .keepAlways
            add(expectedAttachment)
            XCTFail("Snapshot \(name) changed: \(error)")
        }
    }

    private func snapshotName(
        _ screen: MajorSnapshotScreen,
        _ state: MajorSnapshotState,
        _ appearance: ColorScheme,
        _ size: DynamicTypeSize
    ) -> String {
        "\(screen.rawValue)-\(state.rawValue)-\(appearance == .dark ? "dark" : "light")-\(size.snapshotName)"
    }

    private func solidImage(color: UIColor, changedPixel: Bool = false, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in
            color.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            if changedPixel {
                UIColor.white.setFill()
                context.cgContext.fill(CGRect(x: 3, y: 3, width: 1, height: 1))
            }
        }
    }

    private static var baselineDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SnapshotBaselines", isDirectory: true)
    }

    private static var recordMarkerURL: URL {
        baselineDirectory.appendingPathComponent(".record-snapshots")
    }
}

private extension DynamicTypeSize {
    var snapshotName: String {
        switch self {
        case .large: "default"
        case .accessibility3: "ax3"
        case .accessibility5: "ax5"
        default: "other"
        }
    }
}
