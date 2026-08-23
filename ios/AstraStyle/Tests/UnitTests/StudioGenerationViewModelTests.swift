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
    @Test("A 429 on generate sets pendingPaywall to studioQuota")
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
