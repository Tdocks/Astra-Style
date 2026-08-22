//
//  OnboardingReferenceTests.swift
//  AstraStyleTests
//
//  §5.1 step 11 — the optional reference photo.
//
//  Three of these tests are about §29 and one is about ADR 0011, and they are
//  the reason this file exists at all. The camera and the picker are system
//  components that cannot be driven from a unit test; the consent gate, the
//  upload timing is pure logic, it is the part that
//  would be catastrophic to get wrong, and none of them is visible in a UI
//  test that only sees the happy path.
//

import Foundation
import Testing
@testable import AstraStyle

// MARK: - Doubles

/// A `ProfileRepository` that counts uploads and can be told to fail them.
///
/// Counting rather than merely recording success, because the strongest
/// assertion in this file is a NEGATIVE one — a skipped photo must produce
/// zero calls — and "zero" is only provable against a double that would have
/// noticed one.
private actor ReferenceProfileRepository: ProfileRepository {
    private(set) var uploadCount = 0
    private(set) var uploadedBytes: [Data] = []
    private(set) var completedPayloads: [OnboardingCompletionPayload] = []
    private(set) var bodyProfileWrites: [BodyProfile] = []
    private var uploadFails: Bool
    private var storedBodyProfile: BodyProfile?

    init(uploadFails: Bool = false, storedBodyProfile: BodyProfile? = nil) {
        self.uploadFails = uploadFails
        self.storedBodyProfile = storedBodyProfile
    }

    func stopFailingUploads() { uploadFails = false }

    func fetchCurrentProfile() async throws -> Profile { SampleData.profile }
    func updateProfile(_ profile: Profile) async throws -> Profile { profile }
    func fetchStyleProfile() async throws -> StyleProfile? { nil }
    func updateStyleProfile(_ styleProfile: StyleProfile) async throws -> StyleProfile { styleProfile }
    func fetchBodyProfile() async throws -> BodyProfile? { storedBodyProfile }

    func updateBodyProfile(_ bodyProfile: BodyProfile) async throws -> BodyProfile {
        bodyProfileWrites.append(bodyProfile)
        storedBodyProfile = bodyProfile
        return bodyProfile
    }

    func fetchLifestyleProfile() async throws -> LifestyleProfile? { nil }
    func updateLifestyleProfile(_ profile: LifestyleProfile) async throws -> LifestyleProfile { profile }

    func completeOnboarding(_ payload: OnboardingCompletionPayload) async throws -> Profile {
        completedPayloads.append(payload)
        return SampleData.profile
    }

    func generateStyleDNA() async throws -> StyleDNA { SampleData.styleDNA }

    func uploadReferenceImage(_ imageData: Data) async throws -> String {
        uploadCount += 1
        uploadedBytes.append(imageData)
        if uploadFails { throw AstraError.network("No connection.") }
        return "users/\(UUID().uuidString.lowercased())/references/\(UUID().uuidString.lowercased()).jpg"
    }

    func exportPersonalData() async throws -> URL { URL(fileURLWithPath: "/tmp/export.json") }
}

// MARK: - The suite

/// `@MainActor` because `OnboardingViewModel` and `SessionStore` both are.
@MainActor
@Suite("Onboarding — reference photo (§5.1 step 11, §29)")
struct OnboardingReferenceTests {

    private let photo = Data("not-really-a-jpeg-but-bytes-are-bytes".utf8)

    private func makeSessionStore() throws -> SessionStore {
        let store = SessionStore(
            apiClient: AstraAPIClient(environment: .preview),
            supabase: AstraSupabaseClientFactory.previewClient,
            keychain: KeychainTokenStore(service: "astra.test.reference.\(UUID().uuidString)")
        )
        try store.adopt(
            AuthSession(
                userID: UUID(),
                accessToken: "test-token",
                refreshToken: "test-refresh",
                expiresAt: .now.addingTimeInterval(3600),
            )
        )
        return store
    }

    private func makeModel(
        repository: ReferenceProfileRepository,
        referenceStore: InMemoryReferenceImageStore = InMemoryReferenceImageStore(),
        draftStore: InMemoryOnboardingDraftStore = InMemoryOnboardingDraftStore(),
    ) throws -> OnboardingViewModel {
        var draft = OnboardingDraft()
        draft.selectedIdentities = [.modernHeritage, .quietLuxury, .smartCasual]
        draft.primaryIdentity = .modernHeritage
        return OnboardingViewModel(
            store: draftStore,
            profileRepository: repository,
            closetRepository: MockClosetRepository(items: []),
            referenceStore: referenceStore,
            sessionStore: try makeSessionStore(),
            draft: draft,
            step: .reference
        )
    }

    // MARK: The §29 consent gate

    @Test("No photo can be stored before consent is acknowledged")
    func captureRequiresConsent() async throws {
        let model = try makeModel(repository: ReferenceProfileRepository())

        await model.setReferenceImage(photo)

        // The acceptance criterion, stated as code: capture does not proceed
        // without acknowledgment. The screen also declines to render the
        // controls, but that is one layout's behaviour — this is the feature's.
        #expect(model.referenceImageData == nil)
        #expect(model.draft.referenceImageFilename == nil)
        #expect(!model.hasGrantedReferenceConsent)
    }

    @Test("Consent is recorded as a moment, not a flag")
    func consentIsATimestamp() async throws {
        let model = try makeModel(repository: ReferenceProfileRepository())
        let before = Date()

        await model.grantReferenceConsent()

        let granted = try #require(model.draft.referenceConsentGrantedAt)
        #expect(granted >= before)
        // Re-granting must not move the timestamp: the consent that matters is
        // the one given the first time, against the wording shown then.
        await model.grantReferenceConsent()
        #expect(model.draft.referenceConsentGrantedAt == granted)
    }

    @Test("Withdrawing consent takes the photo with it")
    func withdrawingConsentRemovesTheImage() async throws {
        let referenceStore = InMemoryReferenceImageStore()
        let model = try makeModel(repository: ReferenceProfileRepository(), referenceStore: referenceStore)

        await model.grantReferenceConsent()
        await model.setReferenceImage(photo)
        let filename = try #require(model.draft.referenceImageFilename)
        #expect(await referenceStore.load(filename: filename) != nil)

        await model.withdrawReferenceConsent()

        #expect(!model.hasGrantedReferenceConsent)
        #expect(model.referenceImageData == nil)
        #expect(model.draft.referenceImageFilename == nil)
        // Not merely forgotten — gone. Keeping the bytes after a withdrawal
        // would leave the app holding a photograph under revoked permission.
        #expect(await referenceStore.load(filename: filename) == nil)
    }

    @Test("Removing the photo clears every trace of it, including an uploaded path")
    func removeClearsEverything() async throws {
        let model = try makeModel(repository: ReferenceProfileRepository())
        await model.grantReferenceConsent()
        await model.setReferenceImage(photo)
        model.draft.referenceStoragePaths = ["users/x/references/y.jpg"]

        await model.removeReferenceImage()

        #expect(model.draft.referenceImageFilename == nil)
        #expect(model.draft.referenceStoragePaths.isEmpty)
        #expect(model.referenceImageData == nil)
    }

    // MARK: Upload timing

    @Test("Nothing is uploaded at capture time — only at submission")
    func uploadHappensOnSubmissionNotCapture() async throws {
        let repository = ReferenceProfileRepository()
        let model = try makeModel(repository: repository)

        await model.grantReferenceConsent()
        await model.setReferenceImage(photo)

        // ADR 0010's "abandoned upload" is precisely the state this assertion
        // rules out: a user who picks a photo and then backs out has left
        // nothing on a server for a retention sweep (which does not exist) to
        // find.
        #expect(await repository.uploadCount == 0)

        await model.submit()

        #expect(await repository.uploadCount == 1)
        #expect(await repository.uploadedBytes.first == photo)
        #expect(model.draft.referenceStoragePaths.count == 1)
    }

    @Test("The uploaded path reaches body_profiles, and nothing else does")
    func pathTravelsInTheSubmissionPayload() async throws {
        let repository = ReferenceProfileRepository()
        let model = try makeModel(repository: repository)

        await model.grantReferenceConsent()
        await model.setReferenceImage(photo)
        await model.submit()

        let payload = try #require(await repository.completedPayloads.first)
        let path = try #require(model.draft.referenceStoragePaths.first)
        #expect(payload.bodyProfile.appearance.referenceSelfiePaths == [path])
        // Spec §15's storage layout, asserted rather than assumed — a path
        // under any other prefix would be rejected by the bucket policies.
        #expect(path.contains("/references/"))
    }

    @Test("Submitting twice does not upload twice")
    func uploadIsIdempotentAcrossSubmissions() async throws {
        let repository = ReferenceProfileRepository()
        let model = try makeModel(repository: repository)

        await model.grantReferenceConsent()
        await model.setReferenceImage(photo)
        await model.submit()
        await model.submit()

        // The guard is `referenceStoragePaths.isEmpty`. Without it, going back
        // from §6.10 and forward again would leave a second object in storage
        // that no row references.
        #expect(await repository.uploadCount == 1)
    }

    @Test("Skipping the step submits cleanly with no paths and no upload")
    func skippingUploadsNothing() async throws {
        let repository = ReferenceProfileRepository()
        let model = try makeModel(repository: repository)

        await model.submit()

        #expect(model.submission == .succeeded)
        #expect(await repository.uploadCount == 0)
        let payload = try #require(await repository.completedPayloads.first)
        #expect(payload.bodyProfile.appearance.referenceSelfiePaths.isEmpty)
        // `FrameProfile` is built to degrade (docs/14 §2): a missing reference
        // image is a normal profile, not a broken one.
        #expect(payload.bodyProfile.appearance.isEmpty)
    }

    // MARK: Failure

    @Test("A failed upload does not fail the submission")
    func uploadFailureIsNotSubmissionFailure() async throws {
        let repository = ReferenceProfileRepository(uploadFails: true)
        let model = try makeModel(repository: repository)

        await model.grantReferenceConsent()
        await model.setReferenceImage(photo)
        await model.submit()

        // The answers are seven screens of work; the photo is optional. Losing
        // the first because the second failed would be the wrong trade by a
        // wide margin.
        #expect(model.submission == .succeeded)
        #expect(await repository.completedPayloads.count == 1)
        #expect(model.referenceUploadFailure != nil)
        #expect(model.draft.referenceStoragePaths.isEmpty)
    }

    @Test("Retrying after a failed upload writes the path to body_profiles")
    func retryPatchesTheProfile() async throws {
        let repository = ReferenceProfileRepository(uploadFails: true)
        let referenceStore = InMemoryReferenceImageStore()
        let model = try makeModel(repository: repository, referenceStore: referenceStore)

        await model.grantReferenceConsent()
        await model.setReferenceImage(photo)
        await model.submit()
        #expect(model.referenceUploadFailure != nil)
        // The local copy is deliberately KEPT when the upload failed, so there
        // is something to retry with.
        let filename = try #require(model.draft.referenceImageFilename)
        #expect(await referenceStore.load(filename: filename) != nil)

        await repository.stopFailingUploads()
        await model.retryReferenceUpload()

        #expect(model.referenceUploadFailure == nil)
        let path = try #require(model.draft.referenceStoragePaths.first)
        // `completeOnboarding` already wrote body_profiles without the path, so
        // the retry has to patch the row as well as upload — otherwise the
        // object exists and nothing points at it.
        let write = try #require(await repository.bodyProfileWrites.last)
        #expect(write.appearance.referenceSelfiePaths == [path])
    }

    // MARK: Resumption

    @Test("A draft naming a photo that no longer exists forgets it")
    func restoreForgetsAMissingFile() async throws {
        let referenceStore = InMemoryReferenceImageStore()
        let draftStore = InMemoryOnboardingDraftStore()

        var saved = OnboardingDraft()
        saved.referenceConsentGrantedAt = .now
        saved.referenceImageFilename = "a-file-that-was-deleted.jpg"
        saved.furthestStepReached = .reference
        await draftStore.save(saved)

        let model = try makeModel(repository: ReferenceProfileRepository(),
                                  referenceStore: referenceStore,
                                  draftStore: draftStore)
        await model.restore()

        // Otherwise the step would claim a photo the user can neither see nor
        // remove, and submission would carry an empty upload.
        #expect(model.draft.referenceImageFilename == nil)
        #expect(model.referenceImageData == nil)
        #expect(model.step == .firstItems)
    }

    @Test("A resumed draft brings the photo back")
    func restoreReloadsTheImage() async throws {
        let referenceStore = InMemoryReferenceImageStore()
        let draftStore = InMemoryOnboardingDraftStore()
        let filename = try #require(await referenceStore.save(photo))

        var saved = OnboardingDraft()
        saved.referenceConsentGrantedAt = .now
        saved.referenceImageFilename = filename
        saved.furthestStepReached = .reference
        await draftStore.save(saved)

        let model = try makeModel(repository: ReferenceProfileRepository(),
                                  referenceStore: referenceStore,
                                  draftStore: draftStore)
        await model.restore()

        #expect(model.referenceImageData == photo)
        #expect(model.hasGrantedReferenceConsent)
    }
}
