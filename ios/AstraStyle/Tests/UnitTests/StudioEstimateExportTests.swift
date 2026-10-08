import Foundation
import Testing
import UIKit
@testable import AstraStyle

@MainActor
@Suite("Studio estimate export")
struct StudioEstimateExportTests {
    @Test("Live exporter retains image dimensions and adds a disclosure footer")
    func labeledPNG() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let imageData = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300), format: format).pngData { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
        let url = URL(fileURLWithPath: "/tmp/source.png")
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"]))
        let exporter = LiveStudioEstimateExporter { _ in (imageData, response) }
        let output = try await exporter.export(imageURL: url)
        defer { try? FileManager.default.removeItem(at: output) }
        let exported = try #require(UIImage(contentsOfFile: output.path))
        #expect(exported.size.width == 200)
        #expect(exported.size.height > 300)
        #expect(try output.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test("Live exporter rejects server errors and invalid image bytes", arguments: [200, 500])
    func invalidDownload(_ status: Int) async throws {
        let url = URL(fileURLWithPath: "/tmp/source.png")
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "image/png"]))
        let exporter = LiveStudioEstimateExporter { _ in (Data("not an image".utf8), response) }
        await #expect(throws: AstraError.self) { try await exporter.export(imageURL: url) }
    }

    private func fixture(status: StudioGenerationStatus = .complete) -> StudioGeneration {
        StudioGeneration(id: UUID(), userID: SampleData.userID, referenceImagePath: "",
                         status: status, resultImagePath: "users/result.png")
    }

    @Test("Completed estimate resolves a fresh image and returns a local share file")
    func exportCompleted() async {
        let repo = MockStudioRepository(), exporter = RecordingEstimateExporter()
        let generation = fixture()
        await repo.seed(generation)
        let model = StudioGenerationDetailViewModel(generationID: generation.id, studioRepository: repo,
            imageURLResolver: MockClosetImageURLResolver(), exporter: exporter)
        await model.refresh()
        await model.prepareExport()
        #expect(model.exportURL == exporter.output)
        #expect(exporter.calls == 1)
        #expect(model.exportError == nil)
        #expect(!model.isExporting)
    }

    @Test("Download failure keeps the completed estimate available for retry")
    func exportFailure() async {
        let repo = MockStudioRepository(), exporter = RecordingEstimateExporter()
        exporter.shouldFail = true
        let generation = fixture()
        await repo.seed(generation)
        let model = StudioGenerationDetailViewModel(generationID: generation.id, studioRepository: repo,
            imageURLResolver: MockClosetImageURLResolver(), exporter: exporter)
        await model.refresh()
        await model.prepareExport()
        #expect(model.exportURL == nil)
        #expect(model.exportError != nil)
        guard case .loaded = model.state else { Issue.record("Lost estimate on export failure"); return }
        exporter.shouldFail = false
        await model.prepareExport()
        #expect(model.exportURL != nil)
        #expect(model.exportError == nil)
    }

    @Test("Deleted estimate is rechecked before exporting")
    func deletedAfterLoad() async {
        let repo = MockStudioRepository(), exporter = RecordingEstimateExporter()
        var generation = fixture()
        await repo.seed(generation)
        let model = StudioGenerationDetailViewModel(generationID: generation.id, studioRepository: repo,
            imageURLResolver: MockClosetImageURLResolver(), exporter: exporter)
        await model.refresh()
        generation.deletedAt = .now
        await repo.seed(generation)
        await model.prepareExport()
        #expect(exporter.calls == 0)
        #expect(model.exportURL == nil)
        #expect(model.exportError != nil)
    }

    @Test("Failed estimates cannot be exported")
    func incomplete() async {
        let repo = MockStudioRepository(), exporter = RecordingEstimateExporter()
        let generation = fixture(status: .failed)
        await repo.seed(generation)
        let model = StudioGenerationDetailViewModel(generationID: generation.id, studioRepository: repo,
            imageURLResolver: MockClosetImageURLResolver(), exporter: exporter)
        await model.refresh()
        await model.prepareExport()
        #expect(exporter.calls == 0)
    }
}

@MainActor
private final class RecordingEstimateExporter: StudioEstimateExporting {
    var calls = 0
    var shouldFail = false
    let output = URL(fileURLWithPath: "/tmp/astra-test-estimate.png")
    func export(imageURL: URL) async throws -> URL {
        calls += 1
        if shouldFail { throw AstraError.network("Download failed") }
        return output
    }
}
