import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("Home inspiration")
struct InspirationViewModelTests {
    @Test("Inspiration is usable without selecting closet pieces")
    func inspirationWithoutCloset() async {
        let model = InspirationViewModel(closetOnly: false, container: .preview())
        #expect(!model.canGenerate)
        await model.prepare()
        #expect(model.canGenerate)
        #expect(model.selectedItemIDs.isEmpty)
        #expect(model.contextSummary.contains("weather"))
    }

    @Test("Closet generation requires selection within the server limit")
    func selectionLimits() async {
        let model = InspirationViewModel(closetOnly: true, container: .preview())
        await model.prepare()
        model.selectedItemIDs = []
        #expect(!model.canGenerate)
        model.selectedItemIDs = Set((0..<13).map { _ in UUID() })
        #expect(!model.canGenerate)
    }

    @Test("Inspiration request keeps the reference-photo consent separate")
    func inspirationRequest() async throws {
        let repository = MockStudioRepository()
        let result = try await repository.startGeneration(.init(
            referenceImagePath: "", inspirationMode: "inspiration",
            inspirationContext: "Rain today", inspirationInstructions: "More casual",
            hasUserConsent: false
        ))
        #expect(result.status == .queued)
        #expect(result.referenceImagePath.isEmpty)
        do {
            _ = try await repository.startGeneration(.init(referenceImagePath: "photo", hasUserConsent: false))
            Issue.record("Reference photos must still require consent")
        } catch {
            #expect(error is AstraError)
        }
    }
}
