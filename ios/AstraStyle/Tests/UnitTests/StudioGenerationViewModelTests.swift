//
//  StudioGenerationViewModelTests.swift
//  AstraStyleTests
//
//  Wave E: consent must be current before generate; polling reaches
//  complete on the mock provider; stale terms are refused.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Studio generation")
@MainActor
struct StudioGenerationViewModelTests {

    @Test("Missing consent does not start a job")
    func missingConsentFailsLoud() async {
        let studio = MockStudioRepository()
        let model = makeModel(studio: studio)
        model.pollInterval = .zero
        await model.onAppear()
        await model.generate()

        guard case .failed(let error) = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
        #expect(error.category == .validation)
        #expect(await studioJobCount(studio) == 0)
    }

    @Test("Consent plus an existing reference polls through to complete")
    func pollingCompletesOnMock() async throws {
        let studio = MockStudioRepository()
        let profile = MockProfileRepository(bodyProfile: bodyWithReference())
        let model = makeModel(studio: studio, profile: profile)
        model.pollInterval = .zero
        await model.onAppear()
        model.grantConsent()
        #expect(model.canGenerate)
        await model.generate()

        guard case .complete = model.phase else {
            Issue.record("expected .complete, got \(model.phase)")
            return
        }
        #expect(model.generation?.status == .complete)
        #expect(model.resultImageURL != nil)
    }

    @Test("Provider retry reuses the failed generation instead of consuming a new trial")
    func providerFailureRetryReusesGeneration() async {
        let studio = MockStudioRepository(failFirstGeneration: true)
        let model = makeModel(studio: studio)
        model.pollInterval = .zero
        await model.onAppear()
        model.grantConsent()
        await model.generate()

        guard case .failed = model.phase else {
            Issue.record("expected the provider failure to be shown")
            return
        }
        let failedID = model.generation?.id
        #expect(model.generation?.isRetryableWithoutCharge == true)
        #expect(await studioJobCount(studio) == 1)

        await model.retry()

        guard case .complete = model.phase else {
            Issue.record("expected the retry to complete, got \(model.phase)")
            return
        }
        #expect(model.generation?.id == failedID)
        #expect(await studioJobCount(studio) == 1)
        #expect(await studio.retryCountValue() == 1)
    }

    @Test("Stale terms are refused before a job is stored")
    func staleTermsRefused() async {
        let studio = MockStudioRepository()
        do {
            _ = try await studio.startGeneration(
                StudioGenerationRequest(
                    referenceImagePath: "users/x/references/y.jpg",
                    hasUserConsent: true,
                    consentTermsVersion: "1999-01-01"
                )
            )
            Issue.record("stale terms should throw")
        } catch let error as AstraError {
            #expect(error.category == .validation)
        } catch {
            Issue.record("expected AstraError, got \(error)")
        }
    }
}

@Suite("Studio consent wire")
struct StudioConsentWireTests {
    @Test("Attestation encodes acknowledged and terms_version, matching the Edge schema")
    func encodesTermsVersionKey() throws {
        let attestation = StudioConsentAttestation(acknowledged: true, termsVersion: StudioConsentTerms.currentVersion)
        let data = try JSONEncoder().encode(attestation)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["acknowledged"] as? Bool == true)
        #expect(object?["terms_version"] as? String == "2026-08-17")
        #expect(object?["termsVersion"] == nil)
        #expect(StudioConsentTerms.currentVersion == "2026-08-17")
    }
}

@Suite("Studio trial paywall")
@MainActor
struct StudioQuotaViewModelTests {
    @Test("Premium monthly exhaustion displays the error without an upgrade paywall")
    func monthlyLimitDoesNotUpsell() async {
        let model = makeModel(studio: MockStudioRepository(monthlyQuotaExhausted: true))
        await model.onAppear()
        #expect(model.quotaSummary.contains("0 of 20"))
        model.grantConsent()
        await model.generate()
        #expect(model.pendingPaywall == nil)
        guard case .failed(let error) = model.phase else {
            Issue.record("Expected a monthly allowance error")
            return
        }
        #expect(error.message.contains("monthly preview allowance"))
    }

    @Test("An accepted job refreshes the remaining allowance")
    func acceptedJobRefreshesQuota() async {
        let model = makeModel(studio: MockStudioRepository())
        model.pollInterval = .zero
        await model.onAppear()
        #expect(model.quotaSummary.contains("20 of 20"))
        model.grantConsent()
        await model.generate()
        #expect(model.quotaSummary.contains("19 of 20"))
    }

    @Test("Free trial exhaustion presents the upgrade paywall")
    func rateLimitPresentsPaywall() async {
        let studio = MockStudioRepository(quotaExhausted: true)
        let model = makeModel(studio: studio)
        model.pollInterval = .zero
        await model.onAppear()
        model.grantConsent()
        await model.generate()
        #expect(model.pendingPaywall == .studioQuota)
        guard case .failed(let error) = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
        #expect(error.category == .rateLimited)
    }
}

@MainActor
private func makeModel(
    studio: MockStudioRepository,
    profile: MockProfileRepository = MockProfileRepository(bodyProfile: bodyWithReference())
) -> StudioGenerationViewModel {
    StudioGenerationViewModel(
        outfitID: UUID(),
        studioRepository: studio,
        profileRepository: profile,
        imageURLResolver: MockClosetImageURLResolver()
    )
}

private func bodyWithReference() -> BodyProfile {
    var appearance = AppearanceProfile()
    appearance.referenceSelfiePaths = ["users/preview/references/selfie.jpg"]
    return BodyProfile(userID: SampleData.userID, appearance: appearance)
}

private func studioJobCount(_ studio: MockStudioRepository) async -> Int {
    (try? await studio.fetchGenerations().count) ?? 0
}
