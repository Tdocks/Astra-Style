import Foundation
import Testing
@testable import AstraStyle

@Suite("Studio image descriptions")
@MainActor
struct StudioImageDescriptionTests {
    @Test("Automatic description uses the actual structured garment prompt")
    func automaticDescription() {
        let generation = StudioGeneration(id: UUID(), userID: SampleData.userID, referenceImagePath: "",
            promptPayload: .object(["garments": .array([.object(["normalizedTitle": .string("linen trousers"), "colorDescription": .string("navy")])])]))
        #expect(generation.imageDescription.contains("navy linen trousers"))
        #expect(generation.imageDescription.contains("visual estimate"))
    }

    @Test("Description save persists and blank restores automatic description")
    func saveAndReset() async throws {
        let repo = MockStudioRepository()
        let generation = StudioGeneration(id: UUID(), userID: SampleData.userID, referenceImagePath: "", status: .complete)
        await repo.seed(generation)
        let updated = try await repo.updateImageDescription(id: generation.id, description: "  Navy trousers and a white shirt.  ")
        #expect(updated.imageDescription == "Navy trousers and a white shirt.")
        #expect(try await repo.fetchGeneration(id: generation.id).altDescription == updated.altDescription)
        let reset = try await repo.updateImageDescription(id: generation.id, description: " \n ")
        #expect(reset.altDescription == nil)
        #expect(reset.imageDescription.contains("visual estimate"))
    }

    @Test("Long descriptions, deleted images and active images cannot be edited")
    func invalidEdits() async throws {
        #expect(throws: AstraError.self) { try StudioGeneration.validatedDescription(String(repeating: "a", count: 1001)) }
        let repo = MockStudioRepository()
        for generation in [StudioGeneration(id: UUID(), userID: SampleData.userID, referenceImagePath: "", status: .generating),
            StudioGeneration(id: UUID(), userID: SampleData.userID, referenceImagePath: "", status: .complete, deletedAt: .now)] {
            await repo.seed(generation)
            await #expect(throws: AstraError.self) { try await repo.updateImageDescription(id: generation.id, description: "An outfit") }
        }
    }
}
