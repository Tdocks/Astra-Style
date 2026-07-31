//
//  StyleDNAResultTests.swift
//  AstraStyleTests
//
//  The §6.10 result step's behaviour, exercised through
//  `OnboardingViewModel` — the layer that decides what the screen is shown,
//  and the only layer where the three outcomes that matter can be pinned
//  without a simulator.
//
//  WHAT IS WORTH PINNING HERE, AND WHY THESE CASES.
//
//  The rich profile is the case everyone writes and the case that never
//  breaks. The two that break are the ones below it: a SPARSE profile, which
//  is the normal case rather than an edge case (a skipped quiz, or §6.9
//  dimensions have no imagery yet, so they arrive absent), and a NULL primary
//  identity, which the endpoint returns deliberately when it has nothing to go
//  on. Both are one careless `?? "Smart Casual"` away from becoming a screen
//  that presents a guess in the same voice as an answer — and that mistake
//  compiles, renders, and looks better than the correct behaviour.
//
//  The guest case is here for a different reason: ADR 0011 says a guest never
//  touches Supabase, and the only way to prove the result step honours that is
//  to count the calls it makes.
//

import Foundation
import Testing
@testable import AstraStyle

// MARK: - Doubles

/// A `ProfileRepository` that records what it was asked for and returns a
/// scripted sequence of Style DNA documents.
///
/// A sequence rather than one fixed value, because the regenerate assertions
/// are precisely about the SECOND result differing from the first — a stub
/// returning one document forever could not tell a working regenerate from a
/// no-op, which is the failure the Phase 2 exit criterion names.
private actor ScriptedProfileRepository: ProfileRepository {
    enum Failure: Error, LocalizedError {
        case generation
        case write

        var errorDescription: String? {
            switch self {
            case .generation: "Kyra couldn't finish that."
            case .write: "Couldn't save your style profile."
            }
        }
    }

    private var documents: [StyleDNA]
    private var generationFailures: Int
    private var writeFails: Bool
    private var storedStyleProfile: StyleProfile?

    private(set) var completeOnboardingCount = 0
    private(set) var generateCount = 0
    private(set) var updateStyleProfileCount = 0
    private(set) var lastWrittenStyleProfile: StyleProfile?
    private(set) var uploadedReferenceImages: [Data] = []
    private var referenceUploadFails = false

    init(
        documents: [StyleDNA],
        generationFailures: Int = 0,
        writeFails: Bool = false,
        referenceUploadFails: Bool = false,
        storedStyleProfile: StyleProfile? = nil
    ) {
        self.documents = documents
        self.generationFailures = generationFailures
        self.writeFails = writeFails
        self.referenceUploadFails = referenceUploadFails
        self.storedStyleProfile = storedStyleProfile
    }

    func fetchCurrentProfile() async throws -> Profile { SampleData.profile }
    func updateProfile(_ profile: Profile) async throws -> Profile { profile }

    func fetchStyleProfile() async throws -> StyleProfile? { storedStyleProfile }

    func updateStyleProfile(_ styleProfile: StyleProfile) async throws -> StyleProfile {
        updateStyleProfileCount += 1
        if writeFails { throw Failure.write }
        lastWrittenStyleProfile = styleProfile
        storedStyleProfile = styleProfile
        return styleProfile
    }

    func fetchBodyProfile() async throws -> BodyProfile? { nil }
    func updateBodyProfile(_ bodyProfile: BodyProfile) async throws -> BodyProfile { bodyProfile }
    func fetchLifestyleProfile() async throws -> LifestyleProfile? { nil }
    func updateLifestyleProfile(_ lifestyleProfile: LifestyleProfile) async throws -> LifestyleProfile {
        lifestyleProfile
    }

    func completeOnboarding(_ payload: OnboardingCompletionPayload) async throws -> Profile {
        completeOnboardingCount += 1
        storedStyleProfile = payload.styleProfile
        return SampleData.profile
    }

    func generateStyleDNA() async throws -> StyleDNA {
        generateCount += 1
        if generationFailures > 0 {
            generationFailures -= 1
            throw Failure.generation
        }
        // The last document repeats once the script runs out, so a test that
        // only cares about the first result does not have to script every call.
        let index = min(generateCount - 1, documents.count - 1)
        guard documents.indices.contains(index) else { throw Failure.generation }
        let document = documents[index]
        // Mirrors the Edge Function: generating WRITES the four columns it owns
        // back onto `style_profiles`. Without this the stub would hand back a
        // row the real backend never produces, and the read-modify-write test
        // below would be proving something about the double instead of about
        // the view model.
        if let storedStyleProfile {
            self.storedStyleProfile = document.applyingSummary(to: storedStyleProfile)
        }
        return document
    }

    /// Records the bytes as well as the count: `OnboardingReferenceTests`
    /// asserts that a guest's photo never reaches this method at all, and
    /// "never called" is only provable if the double can be asked.
    func uploadReferenceImage(_ imageData: Data) async throws -> String {
        uploadedReferenceImages.append(imageData)
        if referenceUploadFails { throw Failure.write }
        return "users/\(UUID().uuidString.lowercased())/references/\(UUID().uuidString.lowercased()).jpg"
    }

    func exportPersonalData() async throws -> URL { URL(fileURLWithPath: "/tmp/export.json") }
}

private actor MemoryDraftStore: OnboardingDraftStoring {
    private var draft: OnboardingDraft?
    private(set) var clearCount = 0

    func load() async -> OnboardingDraft? { draft }
    func save(_ draft: OnboardingDraft) async { self.draft = draft }
    func clear() async {
        clearCount += 1
        draft = nil
    }
}

// MARK: - Fixtures

private enum StyleDNAFixtures {

    /// Everything populated — the straightforward case.
    static let rich = SampleData.styleDNA

    /// What the endpoint actually returns for a man who answered §6.5 and
    /// nothing else, transcribed from `deterministicStylist.ts`'s behaviour:
    /// the identity-derived sections are present, the lifestyle-derived ones
    /// are not, no axis was measured, and `open_questions` names what would
    /// sharpen it. This is the COMMON shape, not a degenerate one.
    static let sparse = StyleDNA(
        primaryIdentity: .minimalist,
        identityBasis: "the identity you ranked first",
        secondaryInfluences: [],
        palette: StyleDNAPalette(
            preferredColors: ["black", "bone", "mid grey", "navy"],
            avoidedColors: ["saturated brights"],
            rationale: "Minimalist runs on a tight neutral set so pieces swap without thought."
        ),
        silhouette: StyleDNASilhouette(
            headline: "Clean and close, with nothing extra.",
            detail: "A single-breasted line and a flat-front trouser keep the shape uninterrupted."
        ),
        signatureOpportunities: [
            StyleDNARecommendation(
                title: "A black crew-neck in fine merino",
                reason: "It is the layer this direction is built on and it takes a jacket without bulk."
            )
        ],
        wardrobePriorities: [],
        summary: "You are Minimalist. The palette to build on is black, bone, mid grey and navy.",
        knownInputs: ["the style identities you picked"],
        openQuestions: [
            "What you wear to work. It decides how much of this wardrobe has to be work clothes and how much is yours.",
            "Kyra has not asked you about texture, branding, how current you like things, accessories and contrast yet."
        ],
        measuredDimensions: [],
        modelIdentifier: "astra-deterministic-stylist/1"
    )

    /// No identity and no dress code: the server returns a null identity rather
    /// than inventing one, and every identity-derived section comes back empty
    /// while the honest ones come back full.
    static let noIdentity = StyleDNA(
        primaryIdentity: nil,
        identityBasis: "",
        secondaryInfluences: [],
        palette: StyleDNAPalette(
            preferredColors: [],
            avoidedColors: [],
            rationale: "There is no palette yet. A palette follows from a direction, and the direction question has not been answered."
        ),
        silhouette: StyleDNASilhouette(
            headline: "Not enough to call yet.",
            detail: "Cut advice needs either a direction or a measurement to be worth anything, and neither has been given."
        ),
        signatureOpportunities: [],
        wardrobePriorities: [],
        summary: "There is not enough here yet to call a direction, and guessing one would be worse than saying so.",
        knownInputs: [],
        openQuestions: [
            "Which three style identities look like you. It is the single answer that changes the most here."
        ],
        measuredDimensions: [],
        modelIdentifier: "astra-deterministic-stylist/1"
    )

    /// A different result from `rich`, used to prove a regenerate CHANGED
    /// something rather than merely completing.
    static let regenerated = StyleDNA(
        primaryIdentity: .executive,
        identityBasis: "the identity you ranked first",
        secondaryInfluences: [.quietLuxury],
        palette: StyleDNAPalette(
            preferredColors: ["navy", "charcoal", "white"],
            avoidedColors: ["neon brights"],
            rationale: "Executive runs on a narrow, dark set that reads the same in every room."
        ),
        silhouette: StyleDNASilhouette(
            headline: "Sharp shoulder, clean drape.",
            detail: "A structured shoulder holds the line of a jacket through a long day."
        ),
        signatureOpportunities: [
            StyleDNARecommendation(title: "A navy worsted suit", reason: "It is the piece this direction is measured by.")
        ],
        wardrobePriorities: [
            StyleDNAPriority(rank: 1, title: "One suit that fits properly", reason: "Everything else is judged against it.")
        ],
        summary: "You are Executive.",
        knownInputs: ["the style identities you picked"],
        openQuestions: [],
        measuredDimensions: ["formality"],
        modelIdentifier: "astra-deterministic-stylist/1"
    )
}

// MARK: - The suite

/// `@MainActor` because `OnboardingViewModel` and `SessionStore` both are.
@MainActor
@Suite("Style DNA result step (spec §6.10)")
struct StyleDNAResultTests {

    private func makeSessionStore(isGuest: Bool) throws -> SessionStore {
        let apiClient = AstraAPIClient(environment: .preview)
        let store = SessionStore(
            apiClient: apiClient,
            supabase: AstraSupabaseClientFactory.previewClient,
            keychain: KeychainTokenStore(service: "astra.test.style-dna.\(UUID().uuidString)")
        )
        try store.adopt(
            AuthSession(
                userID: UUID(),
                accessToken: "test-token",
                refreshToken: "test-refresh",
                expiresAt: .now.addingTimeInterval(3600),
                isGuest: isGuest
            )
        )
        return store
    }

    private func answeredDraft() -> OnboardingDraft {
        var draft = OnboardingDraft()
        draft.goals = [.shopMoreIntelligently]
        draft.selectedIdentities = [.modernHeritage, .quietLuxury, .smartCasual]
        draft.primaryIdentity = .modernHeritage
        draft.furthestStepReached = .result
        return draft
    }

    private func makeModel(
        repository: ScriptedProfileRepository,
        store: MemoryDraftStore = MemoryDraftStore(),
        isGuest: Bool = false
    ) throws -> OnboardingViewModel {
        OnboardingViewModel(
            store: store,
            profileRepository: repository,
            // Seeded empty rather than with `SampleData`: §6.10's assertions
            // are about Style DNA, and a closet full of fixtures here would
            // only make the failure messages harder to read.
            closetRepository: MockClosetRepository(items: []),
            referenceStore: InMemoryReferenceImageStore(),
            sessionStore: try makeSessionStore(isGuest: isGuest),
            draft: answeredDraft(),
            step: .result
        )
    }

    // MARK: Case 1 — a rich profile

    @Test("A full profile submits once, generates once, and lands on a result with all six sections")
    func richProfileRenders() async throws {
        let repository = ScriptedProfileRepository(documents: [StyleDNAFixtures.rich])
        let model = try makeModel(repository: repository)

        await model.loadStyleDNA()

        let dna = try #require(model.currentStyleDNA)
        #expect(dna.primaryIdentity == .modernHeritage)
        #expect(!dna.secondaryInfluences.isEmpty)
        #expect(!dna.palette.preferredColors.isEmpty)
        #expect(!dna.silhouette.headline.isEmpty)
        #expect(!dna.signatureOpportunities.isEmpty)
        #expect(!dna.wardrobePriorities.isEmpty)
        #expect(!dna.needsMoreInput)

        // Submission comes FIRST. Generating before the answers are written
        // reads an empty style_profiles row and returns a null identity for
        // every brand-new user — the whole reason submission moved to the top
        // of this step.
        #expect(await repository.completeOnboardingCount == 1)
        #expect(await repository.generateCount == 1)
        #expect(model.styleDNAState == .ready(StyleDNAFixtures.rich))
    }

    @Test("Re-entering the step does not pay for a second generation")
    func loadIsIdempotent() async throws {
        let repository = ScriptedProfileRepository(documents: [StyleDNAFixtures.rich])
        let model = try makeModel(repository: repository)

        await model.loadStyleDNA()
        await model.loadStyleDNA()
        await model.loadStyleDNA()

        #expect(await repository.generateCount == 1)
        #expect(await repository.completeOnboardingCount == 1)
    }

    // MARK: Case 2 — a sparse profile

    @Test("A sparse result is a result, not an empty state")
    func sparseProfileIsUsable() async throws {
        let repository = ScriptedProfileRepository(documents: [StyleDNAFixtures.sparse])
        let model = try makeModel(repository: repository)

        await model.loadStyleDNA()

        let dna = try #require(model.currentStyleDNA)
        // The identity-derived half is real content and must render.
        #expect(dna.primaryIdentity == .minimalist)
        #expect(dna.palette.preferredColors.count == 4)
        #expect(!dna.silhouette.detail.isEmpty)
        #expect(dna.signatureOpportunities.count == 1)
        // The lifestyle-derived half is genuinely absent, and absence here is
        // not a failure — it is what the screen omits rather than boxes.
        #expect(dna.wardrobePriorities.isEmpty)
        #expect(dna.secondaryInfluences.isEmpty)
        #expect(dna.measuredDimensions.isEmpty)
        // And the honest half says so. A sparse result with no open questions
        // would be indistinguishable from a complete one, which is exactly the
        // dishonesty these fields exist to prevent.
        #expect(dna.openQuestions.count == 2)
        #expect(!dna.knownInputs.isEmpty)
        #expect(!dna.needsMoreInput)
    }

    @Test("Every palette colour the server sends is displayable, with or without a swatch")
    func sparsePaletteResolvesToSwatches() {
        let swatches = AstraGarmentColor.swatches(for: StyleDNAFixtures.sparse.palette.preferredColors)
        #expect(swatches.count == 4)
        // The name is always shown; only the square is optional.
        #expect(swatches.allSatisfy { !$0.name.isEmpty })
        #expect(swatches.allSatisfy { $0.hex != nil })

        // "saturated brights" is a category, not a colour. No swatch is the
        // honest answer — a rectangle invented for it would be the app
        // asserting a colour nobody chose.
        let category = AstraGarmentColor.swatch(for: "saturated brights")
        #expect(category.hex == nil)
        #expect(category.name == "saturated brights")

        // Head-final resolution, so a modifier this build has never seen still
        // paints the right family rather than nothing.
        #expect(AstraGarmentColor.swatch(for: "tobacco brown").hex != nil)
        #expect(AstraGarmentColor.swatch(for: "washed olive").hex == AstraGarmentColor.swatch(for: "olive").hex)
        #expect(AstraGarmentColor.swatch(for: "  Navy  ").hex == AstraGarmentColor.swatch(for: "navy").hex)
        #expect(AstraGarmentColor.swatch(for: "zorbium").hex == nil)
    }

    // MARK: Case 3 — no primary identity

    @Test("A null identity stays null — nothing invents a direction")
    func nullIdentityIsNotBackfilled() async throws {
        let repository = ScriptedProfileRepository(documents: [StyleDNAFixtures.noIdentity])
        let model = try makeModel(repository: repository)

        await model.loadStyleDNA()

        let dna = try #require(model.currentStyleDNA)
        #expect(dna.primaryIdentity == nil)
        #expect(dna.needsMoreInput)
        #expect(!dna.identityWasInferred)
        // The result still ARRIVED. A null identity is an outcome, not an
        // error, so the step must not be sitting in a failure state.
        #expect(model.styleDNAState == .ready(StyleDNAFixtures.noIdentity))
        // And there is still something to show: the server's own explanation
        // and the silhouette section's "not enough to call yet".
        #expect(!dna.summary.isEmpty)
        #expect(!dna.silhouette.headline.isEmpty)
        #expect(!dna.openQuestions.isEmpty)
    }

    @Test("An inferred identity is distinguishable from a chosen one")
    func inferredIdentityIsFlagged() {
        var inferred = StyleDNAFixtures.rich
        inferred.identityBasis = "your business casual dress code — a starting point, not something you told us"
        #expect(inferred.identityWasInferred)
        #expect(!StyleDNAFixtures.rich.identityWasInferred)
    }

    // MARK: Guests (ADR 0011)

    @Test("A guest reaches a coherent outcome and makes no Style DNA call at all")
    func guestNeverCallsTheEndpoint() async throws {
        let repository = ScriptedProfileRepository(documents: [StyleDNAFixtures.rich])
        let model = try makeModel(repository: repository, isGuest: true)

        await model.loadStyleDNA()

        #expect(model.styleDNAState == .guestPreview)
        #expect(model.currentStyleDNA == nil)
        // Neither call may happen: a guest has no server profile to write and
        // none to generate from.
        #expect(await repository.completeOnboardingCount == 0)
        #expect(await repository.generateCount == 0)
        // Not a spinner and not a failure — the two things a guest must never
        // be left looking at here.
        #expect(!model.isWorkingOnStyleDNA)
        if case .failed = model.styleDNAState { Issue.record("A guest must not see a failure state") }
    }

    @Test("A guest's edit changes his saved answers without touching the network")
    func guestEditStaysLocal() async throws {
        let repository = ScriptedProfileRepository(documents: [StyleDNAFixtures.rich])
        let store = MemoryDraftStore()
        let model = try makeModel(repository: repository, store: store, isGuest: true)

        await model.loadStyleDNA()
        await model.regenerate(identities: [.executive, .minimalist, .creative], primary: .executive)

        #expect(model.draft.primaryIdentity == .executive)
        #expect(model.styleDNAState == .guestPreview)
        #expect(await repository.updateStyleProfileCount == 0)
        #expect(await repository.generateCount == 0)
    }

    // MARK: Edit and regenerate (the Phase 2 exit criterion)

    @Test("Editing the identity writes it, regenerates, and the result changes")
    func regenerateChangesTheResult() async throws {
        let repository = ScriptedProfileRepository(
            documents: [StyleDNAFixtures.rich, StyleDNAFixtures.regenerated]
        )
        let model = try makeModel(repository: repository)

        await model.loadStyleDNA()
        let before = try #require(model.currentStyleDNA)

        await model.regenerate(identities: [.executive, .quietLuxury, .minimalist], primary: .executive)
        let after = try #require(model.currentStyleDNA)

        #expect(before != after)
        #expect(after.primaryIdentity == .executive)
        #expect(model.styleDNAState == .ready(StyleDNAFixtures.regenerated))

        // The edit reached `style_profiles` before the endpoint read it back —
        // two calls in that order, which is the only reason the second document
        // could differ from the first.
        #expect(await repository.updateStyleProfileCount == 1)
        #expect(await repository.generateCount == 2)

        let written = try #require(await repository.lastWrittenStyleProfile)
        #expect(written.primaryIdentity == .executive)
        // The primary is excluded from the secondaries rather than duplicated
        // across both columns.
        #expect(written.secondaryIdentities == [.quietLuxury, .minimalist])
        // The draft carries the edit too, so going back shows what he now says.
        #expect(model.draft.primaryIdentity == .executive)
    }

    @Test("A regenerate carries the columns the generator owns rather than blanking them")
    func regeneratePreservesGeneratedColumns() async throws {
        let repository = ScriptedProfileRepository(
            documents: [StyleDNAFixtures.rich, StyleDNAFixtures.regenerated]
        )
        let model = try makeModel(repository: repository)

        // The first generation writes formality/logo/trend/accessory onto the
        // row, exactly as the Edge Function does.
        await model.loadStyleDNA()
        await model.regenerate(identities: [.executive, .quietLuxury, .minimalist], primary: .executive)

        // Read-modify-write, not compose-from-draft. Building the row locally
        // from the draft would send nils for all four of those columns on every
        // edit, and the endpoint would then generate from a profile the user
        // never edited that way.
        let written = try #require(await repository.lastWrittenStyleProfile)
        #expect(written.logoTolerance == StyleDNAFixtures.rich.logoTolerance)
        #expect(written.trendTolerance == StyleDNAFixtures.rich.trendTolerance)
        #expect(written.formalityPreference == StyleDNAFixtures.rich.formalityPreference)
        #expect(written.accessoryPreference == StyleDNAFixtures.rich.accessoryPreference)
    }

    @Test("A failed regenerate keeps the result the user already had")
    func failedRegenerateKeepsPreviousResult() async throws {
        let repository = ScriptedProfileRepository(
            documents: [StyleDNAFixtures.rich, StyleDNAFixtures.regenerated],
            generationFailures: 0,
            writeFails: true
        )
        let model = try makeModel(repository: repository)

        await model.loadStyleDNA()
        let before = try #require(model.currentStyleDNA)

        await model.regenerate(identities: [.executive, .quietLuxury, .minimalist], primary: .executive)

        #expect(model.styleDNAState == .failed(message: "Couldn't save your style profile.", previous: before))
        // The point of the assertion above, stated the way the user sees it:
        // the screen still has something on it.
        #expect(model.currentStyleDNA == before)
    }

    // MARK: Failure and retry

    @Test("A failed generation is retryable without re-submitting the answers")
    func retryDoesNotResubmit() async throws {
        let repository = ScriptedProfileRepository(
            documents: [StyleDNAFixtures.rich],
            generationFailures: 1
        )
        let model = try makeModel(repository: repository)

        await model.loadStyleDNA()
        if case .failed(_, let previous) = model.styleDNAState {
            #expect(previous == nil)
        } else {
            Issue.record("A failed generation must leave the step in a failure state")
        }

        await model.retryStyleDNA()

        #expect(model.styleDNAState == .ready(StyleDNAFixtures.rich))
        // One submission, two generation attempts. Re-submitting on retry
        // would be a second identical write of the whole onboarding payload.
        #expect(await repository.completeOnboardingCount == 1)
        #expect(await repository.generateCount == 2)
    }

    // MARK: Finishing, and going back

    @Test("Finishing leaves the flow without submitting a second time")
    func finishDoesNotResubmit() async throws {
        let repository = ScriptedProfileRepository(documents: [StyleDNAFixtures.rich])
        let model = try makeModel(repository: repository)

        await model.loadStyleDNA()
        #expect(!model.isFinished)

        await model.advance()

        #expect(model.isFinished)
        #expect(await repository.completeOnboardingCount == 1)
    }

    @Test("A guest who finishes still leaves the flow")
    func guestCanFinish() async throws {
        let repository = ScriptedProfileRepository(documents: [StyleDNAFixtures.rich])
        let model = try makeModel(repository: repository, isGuest: true)

        await model.loadStyleDNA()
        await model.advance()

        #expect(model.isFinished)
    }

    @Test("Going back to change an answer discards the result so returning regenerates it")
    func goingBackClearsTheResult() async throws {
        let repository = ScriptedProfileRepository(
            documents: [StyleDNAFixtures.rich, StyleDNAFixtures.regenerated]
        )
        let model = try makeModel(repository: repository)

        await model.loadStyleDNA()
        #expect(model.currentStyleDNA != nil)

        await model.goBack()
        #expect(model.styleDNAState == .idle)
        #expect(model.currentStyleDNA == nil)

        // Forward again: the answers are re-submitted and the result is rebuilt
        // from them, rather than the stale one being shown beside answers that
        // no longer produced it.
        await model.advance()
        await model.loadStyleDNA()
        #expect(await repository.completeOnboardingCount == 2)
        #expect(model.currentStyleDNA == StyleDNAFixtures.regenerated)
    }
}
