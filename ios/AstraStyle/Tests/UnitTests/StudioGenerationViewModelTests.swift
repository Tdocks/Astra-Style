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

    @Test("Submission, queued, generating and finishing progress remain distinct")
    func generationProgressStates() {
        let messages = [nil, StudioGenerationStatus.queued, .generating, .complete]
            .map { StudioGenerationViewModel.progressMessage(for: $0) }
        #expect(Set(messages).count == 4)
        #expect(messages.allSatisfy { !$0.isEmpty })
        #expect(StudioGenerationViewModel.progressMessage(for: .queued).contains("queued"))
    }

    @Test("All eight presets populate editable advanced controls", arguments: StudioPromptPreset.allCases)
    func presetFillsControls(_ preset: StudioPromptPreset) {
        let model = makeModel(studio: MockStudioRepository())
        model.selectedPreset = nil
        model.selectedPreset = preset
        let defaults = preset.controlDefaults
        #expect(model.selectedBackground == defaults.background)
        #expect(model.selectedPose == defaults.pose)
        #expect(model.selectedFormality == defaults.formality)
        #expect(model.paletteText == defaults.palette.joined(separator: ", "))
        #expect(model.selectedSeason != nil)

        model.selectedBackground = .neutral
        model.selectedPose = .seated
        model.selectedFormality = .veryCasual
        model.selectedSeason = .winter
        model.paletteText = "olive"
        #expect(model.selectedPreset == preset)
        #expect(model.selectedBackground == .neutral)
        #expect(model.selectedPose == .seated)
        #expect(model.selectedFormality == .veryCasual)
        #expect(model.selectedSeason == .winter)
        #expect(model.paletteText == "olive")
    }

    @Test("Applying the selected preset again restores its editable defaults")
    func reapplyingSelectedPresetResetsEdits() {
        let model = makeModel(studio: MockStudioRepository())
        model.applyPreset(.vacation)
        model.selectedBackground = .neutral
        model.selectedPose = .seated
        model.selectedFormality = .formal
        model.selectedSeason = .winter
        model.paletteText = "olive"

        model.applyPreset(.vacation)

        let defaults = StudioPromptPreset.vacation.controlDefaults
        #expect(model.selectedPreset == .vacation)
        #expect(model.selectedBackground == defaults.background)
        #expect(model.selectedPose == defaults.pose)
        #expect(model.selectedFormality == defaults.formality)
        #expect(model.selectedSeason == defaults.season)
        #expect(model.paletteText == defaults.palette.joined(separator: ", "))
    }

    @Test("Replacing a reference photo requires new consent and uses the replacement")
    func replacementPhotoNeedsConsent() async {
        let studio = MockStudioRepository()
        let model = makeModel(studio: studio)
        model.pollInterval = .zero
        await model.onAppear()
        let previousReference = model.existingReferencePath
        model.grantConsent()
        model.setPendingImage(Data([1, 2, 3]))
        #expect(!model.hasGrantedConsent)
        #expect(!model.canGenerate)
        await model.generate()
        #expect(await studioJobCount(studio) == 0)

        model.grantConsent()
        await model.generate()
        #expect(model.phase == .complete)
        #expect(model.generation?.referenceImagePath != previousReference)
        #expect(model.generation?.referenceImagePath.contains("/references/") == true)
        model.removePendingImage()
        #expect(!model.hasGrantedConsent)
    }

    @Test("Preset defaults and user overrides reach the generation request")
    func advancedControlsReachProviderRequest() async {
        let studio = MockStudioRepository()
        let model = makeModel(studio: studio)
        model.pollInterval = .zero
        await model.onAppear()
        model.selectedPreset = .vacation
        model.selectedBackground = .neutral
        model.selectedPose = .seated
        model.selectedFormality = .formal
        model.selectedSeason = .winter
        model.paletteText = "olive, cream"
        model.preservesFace = false
        model.preservesBodyProportions = false
        model.preservesHair = false
        model.grantConsent()
        await model.generate()

        let request = await studio.lastGenerationRequest()
        #expect(request?.preset == .vacation)
        #expect(request?.background == .neutral)
        #expect(request?.pose == .seated)
        #expect(request?.formality == .formal)
        #expect(request?.season == .winter)
        #expect(request?.colorPalette == ["olive", "cream"])
        #expect(request?.preserveFace == false)
        #expect(request?.preserveBodyProportions == false)
        #expect(request?.preserveHair == false)
        #expect(request?.hasUserConsent == true)
        #expect(model.phase == .complete)
    }

    @Test("Withdrawing reference consent prevents another provider attempt")
    func withdrawnConsentBlocksRetry() async {
        let studio = MockStudioRepository(failFirstGeneration: true)
        let model = makeModel(studio: studio)
        model.pollInterval = .zero
        await model.onAppear()
        model.grantConsent()
        await model.generate()
        #expect(model.generation?.status == .failed)
        model.withdrawConsent()
        await model.retry()
        #expect(await studio.retryCountValue() == 0)
        guard case .failed(let error) = model.phase else {
            Issue.record("Expected a consent error")
            return
        }
        #expect(error.category == .validation)
    }

    @Test("Consent for a replacement cannot authorize retrying the previous photo")
    func replacementConsentDoesNotAuthorizeOriginalRetry() async {
        let studio = MockStudioRepository(failFirstGeneration: true)
        let model = makeModel(studio: studio)
        model.pollInterval = .zero
        await model.onAppear()
        model.grantConsent()
        await model.generate()
        model.setPendingImage(Data([4, 5, 6]))
        model.grantConsent()
        await model.retry()
        #expect(await studio.retryCountValue() == 0)
        guard case .failed(let error) = model.phase else {
            Issue.record("Expected a photo-specific consent error")
            return
        }
        #expect(error.category == .validation)
    }

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

    @Test("A completed generation gives an explicit reroll a fresh variation nonce")
    func completedGenerationGetsFreshRerollNonce() async {
        let studio = MockStudioRepository()
        let model = makeModel(studio: studio)
        model.pollInterval = .zero
        await model.onAppear()
        model.grantConsent()

        await model.generate()
        await model.generate()

        let requests = await studio.generationRequests()
        #expect(requests.count == 2)
        #expect(requests[0].variationNonce == nil)
        #expect(requests[1].variationNonce != nil)
    }

    @Test("Retrying a failed explicit reroll keeps its nonce and does not submit a new request")
    func failedRerollRetryKeepsNonce() async {
        let studio = MockStudioRepository()
        let model = makeModel(studio: studio)
        model.pollInterval = .zero
        await model.onAppear()
        model.grantConsent()

        await model.generate()
        await studio.failNextGeneration()
        await model.generate()
        let failedRequest = await studio.lastGenerationRequest()
        #expect(failedRequest?.variationNonce != nil)

        await model.retry()

        let requestsAfterRetry = await studio.generationRequests()
        #expect(requestsAfterRetry.count == 2)
        #expect(requestsAfterRetry.last?.variationNonce == failedRequest?.variationNonce)
        #expect(model.phase == .complete)
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
    func typedTrialQuotaPresentsPaywall() async {
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
        #expect(error.category == .subscriptionLimitReached)
        #expect(error.quotaDetails?.limit == "studio_trial_generation")
    }

    @Test("A transport throttle does not present the upgrade paywall")
    func transportThrottleDoesNotUpsell() async {
        let studio = MockStudioRepository()
        await studio.setStartGenerationError(.rateLimited())
        let model = makeModel(studio: studio)
        await model.onAppear()
        model.grantConsent()
        await model.generate()
        #expect(model.pendingPaywall == nil)
        guard case .failed(let error) = model.phase else {
            Issue.record("Expected the transport throttle to remain a retryable error")
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
