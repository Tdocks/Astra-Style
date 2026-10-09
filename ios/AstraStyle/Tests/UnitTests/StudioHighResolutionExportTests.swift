import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("Studio high-resolution export")
struct StudioHighResolutionExportTests {
    private func source(mode: String = "studio", status: StudioGenerationStatus = .complete) -> StudioGeneration {
        let id = UUID()
        let owner = UUID()
        return StudioGeneration(
            id: id,
            userID: owner,
            referenceImagePath: "users/\(owner.uuidString.lowercased())/references/reference.jpg",
            promptPayload: .object(["mode": .string(mode), "resolution": .string("draft")]),
            status: status,
            resultImagePath: "users/\(owner.uuidString.lowercased())/studio/\(id.uuidString.lowercased())/result.png"
        )
    }

    private func makeModel(_ source: StudioGeneration, repo: HiResStudioRepository) -> StudioGenerationDetailViewModel {
        let model = StudioGenerationDetailViewModel(
            generationID: source.id,
            studioRepository: repo,
            imageURLResolver: MockClosetImageURLResolver(),
            exporter: HiResNoOpExporter()
        )
        model.pollInterval = .zero
        return model
    }

    @Test("Photo-source export discloses one render and requires fresh consent before enqueue")
    func photoExportConfirmsFreshConsentAndFollowsChild() async throws {
        let source = source()
        let repo = HiResStudioRepository(source: source)
        let model = makeModel(source, repo: repo)
        await model.onAppear()

        #expect(model.canExportHighResolution)
        await model.prepareHighResolutionExport()
        #expect(model.hasPendingHighResolutionConfirmation)
        #expect(model.highResolutionConfirmationMessage.contains("one of your 5 remaining"))
        #expect(model.requiresHighResolutionPhotoConsent)
        #expect(await repo.exportCallCount == 0)

        await model.confirmHighResolutionExport()

        let consent = try #require(await repo.lastConsent)
        #expect(consent == StudioConsentAttestation(acknowledged: true, termsVersion: StudioConsentTerms.currentVersion))
        #expect(await repo.lastSourceID == source.id)
        #expect(model.highResolutionChild?.status == .complete)
        #expect(model.highResolutionImageURL != nil)
        guard case .loaded(let stillOriginal) = model.state else {
            Issue.record("High-resolution child replaced the source estimate")
            return
        }
        #expect(stillOriginal.id == source.id)
    }

    @Test("Inspiration export has no identity-photo consent requirement")
    func inspirationNeedsNoConsent() async throws {
        var source = source(mode: "inspiration")
        source.referenceImagePath = ""
        let repo = HiResStudioRepository(source: source)
        let model = makeModel(source, repo: repo)
        await model.onAppear()
        await model.prepareHighResolutionExport()

        #expect(!model.requiresHighResolutionPhotoConsent)
        #expect(!model.highResolutionConfirmationMessage.contains("photo-consent terms"))
        await model.confirmHighResolutionExport()
        #expect(await repo.exportCallCount == 1)
        #expect(await repo.lastConsent == nil)
    }

    @Test("Non-Premium or exhausted allowance cannot open export confirmation")
    func entitlementAndAllowanceGates() async {
        let source = source()
        let nonPremium = HiResStudioRepository(source: source, quota: StudioQuota(premium: false, limit: 0, used: 0, remaining: 0, resetsAt: nil))
        let first = makeModel(source, repo: nonPremium)
        await first.onAppear()
        await first.prepareHighResolutionExport()
        #expect(!first.hasPendingHighResolutionConfirmation)
        #expect(first.highResolutionError != nil)
        #expect(await nonPremium.exportCallCount == 0)

        let exhausted = HiResStudioRepository(source: source, quota: StudioQuota(premium: true, limit: 20, used: 20, remaining: 0, resetsAt: nil))
        let second = makeModel(source, repo: exhausted)
        await second.onAppear()
        await second.prepareHighResolutionExport()
        #expect(!second.hasPendingHighResolutionConfirmation)
        #expect(second.highResolutionError != nil)
        #expect(await exhausted.exportCallCount == 0)
    }

    @Test("A changed allowance is disclosed again before the export request")
    func changedQuotaRequiresSecondConfirmation() async {
        let source = source()
        let repo = HiResStudioRepository(source: source, quotas: [
            StudioQuota(premium: true, limit: 20, used: 15, remaining: 5, resetsAt: nil),
            StudioQuota(premium: true, limit: 20, used: 19, remaining: 1, resetsAt: nil),
            StudioQuota(premium: true, limit: 20, used: 19, remaining: 1, resetsAt: nil)
        ])
        let model = makeModel(source, repo: repo)
        await model.onAppear()
        await model.prepareHighResolutionExport()
        await model.confirmHighResolutionExport()
        #expect(await repo.exportCallCount == 0)
        #expect(model.hasPendingHighResolutionConfirmation)
        #expect(model.highResolutionConfirmationMessage.contains("one of your 1 remaining"))
        await model.confirmHighResolutionExport()
        #expect(await repo.exportCallCount == 1)
    }

    @Test("A retryable failed child retries its own lineage without a second quota read")
    func failedChildUsesRetryWithoutAnotherCredit() async {
        let source = source()
        let repo = HiResStudioRepository(source: source, failFirstExport: true)
        let model = makeModel(source, repo: repo)
        await model.onAppear()
        await model.prepareHighResolutionExport()
        await model.confirmHighResolutionExport()
        let child = model.highResolutionChild
        #expect(child?.isRetryableWithoutCharge == true)
        let quotaReads = await repo.quotaReadCount

        await model.retryHighResolutionExport()

        #expect(await repo.retryCount == 1)
        #expect(await repo.quotaReadCount == quotaReads)
        #expect(model.highResolutionChild?.id == child?.id)
        #expect(model.highResolutionChild?.status == .complete)
    }

    @Test("A lost accepted response is reconciled before another credit can be reserved")
    func lostResponseFindsAcceptedChildBeforeQuotaGate() async {
        let source = source()
        let repo = HiResStudioRepository(source: source, failAfterAcceptanceOnce: true)
        let model = makeModel(source, repo: repo)
        await model.onAppear()
        await model.prepareHighResolutionExport()
        await model.confirmHighResolutionExport()
        #expect(model.highResolutionChild == nil)
        #expect(model.highResolutionSubmissionUncertain)
        #expect(model.highResolutionError != nil)

        let quotaReadsAfterAcceptance = await repo.quotaReadCount
        await model.prepareHighResolutionExport()

        #expect(!model.hasPendingHighResolutionConfirmation)
        #expect(await repo.exportCallCount == 1)
        #expect(await repo.quotaReadCount == quotaReadsAfterAcceptance)
        #expect(model.highResolutionChild?.status == .complete)
        #expect(!model.highResolutionSubmissionUncertain)
    }

    @Test("A recreated detail recovers the accepted child before checking an exhausted allowance")
    func recreatedDetailFindsAcceptedChildAtZeroQuota() async {
        let source = source()
        let repo = HiResStudioRepository(source: source, failAfterAcceptanceOnce: true)
        let firstModel = makeModel(source, repo: repo)
        await firstModel.onAppear()
        await firstModel.prepareHighResolutionExport()
        await firstModel.confirmHighResolutionExport()
        #expect(firstModel.highResolutionChild == nil)
        let quotaReadsBeforeReopen = await repo.quotaReadCount
        let exportCallsBeforeReopen = await repo.exportCallCount

        let reopenedModel = makeModel(source, repo: repo)
        await reopenedModel.onAppear()

        #expect(reopenedModel.highResolutionChild != nil)
        #expect(reopenedModel.highResolutionChild?.status == .complete)
        #expect(await repo.quotaReadCount == quotaReadsBeforeReopen)
        #expect(await repo.exportCallCount == exportCallsBeforeReopen)
        #expect(!reopenedModel.highResolutionSubmissionUncertain)
    }

    @Test("A failed lineage lookup leaves the source visible and blocks a possibly duplicate charge")
    func lineageLookupFailureKeepsRetryableSourceVisible() async {
        let source = source()
        let repo = HiResStudioRepository(source: source, failLineageLookup: true)
        let model = makeModel(source, repo: repo)
        await model.onAppear()

        guard case .loaded(let visibleSource) = model.state else {
            Issue.record("A failed child lookup hid the source estimate")
            return
        }
        #expect(visibleSource.id == source.id)
        #expect(model.canExportHighResolution)
        #expect(model.highResolutionError != nil)

        await model.prepareHighResolutionExport()
        #expect(model.highResolutionError != nil)
        #expect(await repo.quotaReadCount == 0)
        #expect(await repo.exportCallCount == 0)
    }

    @Test("A peer-owned export is excluded from the source lineage lookup")
    func lineageLookupExcludesPeerOwnedChild() async throws {
        let source = source()
        let repo = HiResStudioRepository(source: source)
        await repo.seedPeerExport(sourceID: source.id)

        #expect(try await repo.fetchHiResExport(sourceID: source.id) == nil)
    }

    @Test("A high-resolution child cannot itself be exported again")
    func highResolutionChildIsNotASource() async {
        var child = source()
        child.promptPayload = .object([
            "resolution": .string("hi_res"),
            "hi_res_source_generation_id": .string(UUID().uuidString.lowercased())
        ])
        let repo = HiResStudioRepository(source: child)
        let model = makeModel(child, repo: repo)
        await model.onAppear()

        #expect(!model.canExportHighResolution)
        await model.prepareHighResolutionExport()
        #expect(await repo.quotaReadCount == 0)
        #expect(await repo.exportCallCount == 0)
    }
}

@MainActor
private final class HiResNoOpExporter: StudioEstimateExporting {
    func export(imageURL: URL) async throws -> URL { imageURL }
}

private actor HiResStudioRepository: StudioRepository {
    private let source: StudioGeneration
    private var quota: StudioQuota
    private var quotas: [StudioQuota]
    private var generations: [UUID: StudioGeneration]
    private var failFirstExport: Bool
    private var failAfterAcceptanceOnce: Bool
    private var exportChildID: UUID?
    private var exportCalls = 0
    private var retryCalls = 0
    private var quotaReads = 0
    private var latestConsent: StudioConsentAttestation?
    private var latestSourceID: UUID?
    private var failLineageLookup: Bool

    init(source: StudioGeneration, quota: StudioQuota = StudioQuota(premium: true, limit: 20, used: 15, remaining: 5, resetsAt: nil), quotas: [StudioQuota] = [], failFirstExport: Bool = false, failAfterAcceptanceOnce: Bool = false, failLineageLookup: Bool = false) {
        self.source = source
        self.quota = quota
        self.quotas = quotas
        self.generations = [source.id: source]
        self.failFirstExport = failFirstExport
        self.failAfterAcceptanceOnce = failAfterAcceptanceOnce
        self.failLineageLookup = failLineageLookup
    }

    func fetchQuota() async throws -> StudioQuota {
        quotaReads += 1
        if !quotas.isEmpty {
            quota = quotas.removeFirst()
        }
        return quota
    }

    func fetchGenerations() async throws -> [StudioGeneration] { Array(generations.values) }
    func fetchGeneration(id: UUID) async throws -> StudioGeneration {
        guard let generation = generations[id] else { throw AstraError.server("Missing test generation") }
        return generation
    }
    func fetchHiResExport(sourceID: UUID) async throws -> StudioGeneration? {
        if failLineageLookup { throw AstraError.network("Lineage lookup failed") }
        return generations.values
            .filter { generation in
                guard generation.userID == source.userID,
                      case .object(let payload)? = generation.promptPayload,
                      case .string(let lineageSourceID)? = payload["hi_res_source_generation_id"] else { return false }
                return lineageSourceID == sourceID.uuidString.lowercased()
            }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt }
            .first
    }
    func seedPeerExport(sourceID: UUID) {
        let peerID = UUID()
        generations[peerID] = StudioGeneration(
            id: peerID,
            userID: UUID(),
            referenceImagePath: "",
            promptPayload: .object([
                "resolution": .string("hi_res"),
                "hi_res_source_generation_id": .string(sourceID.uuidString.lowercased())
            ]),
            status: .complete,
            resultImagePath: "peer/export.png"
        )
    }
    func startGeneration(_ request: StudioGenerationRequest) async throws -> StudioGeneration {
        throw AstraError.unimplemented("Not needed in this test")
    }
    func fetchStatus(generationID: UUID) async throws -> StudioGeneration {
        guard var generation = generations[generationID] else { throw AstraError.server("Missing test generation") }
        if generation.status == .queued {
            generation.status = .generating
        } else if generation.status == .generating {
            generation.status = .complete
            generation.resultImagePath = "users/\(generation.userID.uuidString.lowercased())/studio/\(generation.id.uuidString.lowercased())/result.png"
        }
        generations[generationID] = generation
        return generation
    }
    func exportHiRes(sourceID: UUID, consent: StudioConsentAttestation?) async throws -> StudioGeneration {
        exportCalls += 1
        latestSourceID = sourceID
        latestConsent = consent
        if let exportChildID, let child = generations[exportChildID] { return child }
        let id = UUID()
        let failed = failFirstExport
        failFirstExport = false
        let child = StudioGeneration(
            id: id,
            userID: source.userID,
            referenceImagePath: source.referenceImagePath,
            promptPayload: .object([
                "resolution": .string("hi_res"),
                "hi_res_source_generation_id": .string(sourceID.uuidString.lowercased()),
                "is_retryable_failure": .bool(failed)
            ]),
            status: failed ? .failed : .queued,
            errorMessage: failed ? "Provider unavailable" : nil
        )
        generations[id] = child
        exportChildID = id
        if failAfterAcceptanceOnce {
            failAfterAcceptanceOnce = false
            quota = StudioQuota(premium: true, limit: 20, used: 20, remaining: 0, resetsAt: nil)
            throw AstraError.network("Response was lost after server acceptance")
        }
        return child
    }
    func retryGeneration(id: UUID) async throws -> StudioGeneration {
        guard var child = generations[id] else { throw AstraError.server("Missing test generation") }
        retryCalls += 1
        child.status = .queued
        child.errorMessage = nil
        child.promptPayload = .object([
            "resolution": .string("hi_res"),
            "hi_res_source_generation_id": .string(source.id.uuidString.lowercased()),
            "is_retryable_failure": .bool(false)
        ])
        generations[id] = child
        return child
    }
    func deleteGeneration(id: UUID) async throws { generations[id] = nil }

    var exportCallCount: Int { exportCalls }
    var retryCount: Int { retryCalls }
    var quotaReadCount: Int { quotaReads }
    var lastConsent: StudioConsentAttestation? { latestConsent }
    var lastSourceID: UUID? { latestSourceID }
}
