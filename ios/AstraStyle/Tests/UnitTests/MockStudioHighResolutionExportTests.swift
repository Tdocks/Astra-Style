import Foundation
import Testing
@testable import AstraStyle

@Suite("Mock Studio high-resolution exports")
struct MockStudioHighResolutionExportTests {
    @Test("Quota reset identity stays stable across repeated reads")
    func repeatedQuotaReadsKeepSameResetIdentity() async throws {
        let repository = MockStudioRepository()

        let first = try await repository.fetchQuota()
        let second = try await repository.fetchQuota()

        #expect(first.resetsAt != nil)
        #expect(first.resetsAt == second.resetsAt)
    }

    @Test("Photo exports require current consent and replay the same child")
    func photoExportRequiresConsentAndIsIdempotent() async throws {
        let owner = SampleData.userID
        let referencePath = "users/\(owner.uuidString.lowercased())/references/\(UUID().uuidString.lowercased()).jpg"
        let repository = MockStudioRepository(referencePhotoPath: referencePath)
        let source = try #require(try await repository.fetchGenerations().first { $0.referenceImagePath == referencePath })

        do {
            _ = try await repository.exportHiRes(sourceID: source.id, consent: nil)
            Issue.record("Photo export should require fresh consent")
        } catch let error as AstraError {
            #expect(error.category == .validation)
        }

        let consent = StudioConsentAttestation(acknowledged: true, termsVersion: StudioConsentTerms.currentVersion)
        let child = try await repository.exportHiRes(sourceID: source.id, consent: consent)
        let replay = try await repository.exportHiRes(sourceID: source.id, consent: nil)

        #expect(child.id == replay.id)
        #expect(child.status == .queued)
        #expect(try await repository.fetchHiResExport(sourceID: source.id)?.id == child.id)
        #expect(try await repository.fetchGenerations().filter { $0.userID == owner }.count == 4)
    }

    @Test("Inspiration exports do not require photo consent")
    func inspirationExportHasNoConsentGate() async throws {
        let repository = MockStudioRepository()
        let source = StudioGeneration(
            id: UUID(),
            userID: SampleData.userID,
            referenceImagePath: "",
            promptPayload: .object(["mode": .string("inspiration")]),
            status: .complete,
            resultImagePath: "users/\(SampleData.userID.uuidString.lowercased())/studio/\(UUID().uuidString.lowercased())/result.png"
        )
        await repository.seed(source)

        let child = try await repository.exportHiRes(sourceID: source.id, consent: nil)

        #expect(child.status == .queued)
        #expect(try await repository.fetchHiResExport(sourceID: source.id)?.id == child.id)
    }
}
