//
//  OnboardingDraftTests.swift
//  AstraStyleTests
//
//  The unit conversion and the "I don't know" state are the two things here
//  that fail silently if wrong — a bad conversion produces a plausible number
//  and a collapsed skip state produces a re-prompt loop. Both are covered
//  first.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Onboarding — measurement entry converts once, in one place")
struct MeasurementEntryTests {

    @Test("Imperial entry converts to centimetres")
    func imperialConverts() {
        let height = MeasurementEntry.provided(71, unit: .imperial)
        // 71" == 180.34cm
        #expect(abs(height.centimetres! - 180.34) < 0.01)
    }

    @Test("Metric entry passes through unconverted")
    func metricPassesThrough() {
        let height = MeasurementEntry.provided(180.3, unit: .metric)
        #expect(abs(height.centimetres! - 180.3) < 0.001)
    }

    @Test("Weight converts on the mass path, not the length path")
    func weightUsesKilograms() {
        let weight = MeasurementEntry.provided(178, unit: .imperial)
        // 178lb == 80.74kg
        #expect(abs(weight.kilograms! - 80.74) < 0.01)
        // The length conversion would give 452cm. A single generic "convert"
        // that guessed the unit family is the trap this separation avoids.
        #expect(weight.centimetres! > 400)
    }

    /// The distinction the whole `State` enum exists for.
    @Test("Declined and unanswered are different, and neither yields a value")
    func declinedIsNotUnanswered() {
        let declined = MeasurementEntry.declined(unit: .imperial)
        let untouched = MeasurementEntry()

        #expect(declined.centimetres == nil)
        #expect(untouched.centimetres == nil)
        // Both produce nil downstream, but the app must be able to tell them
        // apart — one has been answered, the other has not, and only the second
        // may be prompted for again.
        #expect(declined.isAnswered)
        #expect(!untouched.isAnswered)
        #expect(declined != untouched)
    }

    @Test("Zero and negative entries are not treated as measurements")
    func zeroIsNotAMeasurement() {
        #expect(MeasurementEntry.provided(0, unit: .imperial).centimetres == nil)
        #expect(MeasurementEntry.provided(-5, unit: .metric).centimetres == nil)
    }
}

@Suite("Onboarding — draft round-trips and maps to the domain models")
struct OnboardingDraftTests {

    private func filledDraft() -> OnboardingDraft {
        var d = OnboardingDraft()
        d.goals = [.shopMoreIntelligently, .findSignatureStyle]
        d.selectedIdentities = [.quietLuxury, .modernHeritage, .minimalist]
        d.primaryIdentity = .modernHeritage
        d.units = .imperial
        d.height = .provided(71, unit: .imperial)
        d.chest = .provided(44, unit: .imperial)
        d.waist = .provided(34, unit: .imperial)
        d.inseam = .declined(unit: .imperial)
        d.shirtSize = "L"
        d.trouserSize = "34x32"
        d.preferredFit = .tailored
        d.fitIssues = [.largeThighs, .broadChest]
        d.occupationCategory = .technology
        d.monthlyBudget = 250
        d.currency = "GBP"
        d.travelFrequency = "Monthly"
        d.typicalWeek = "Split between home and office"
        d.sustainabilityPreference = "Prefer natural fibres"
        d.quizAnswers = [StylePreferenceQuizAnswer(pairID: "p1", chosenOptionID: "a")]
        return d
    }

    @Test("A filled draft survives a JSON round trip")
    func roundTrips() throws {
        let original = filledDraft()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(OnboardingDraft.self, from: data)
        #expect(restored == original)
    }

    /// Quiz answers are `Encodable`-only on the submission type, so the draft
    /// mirrors them for storage. This is the test that catches the mirror
    /// silently dropping them.
    @Test("Quiz answers survive the round trip")
    func quizAnswersSurvive() throws {
        let data = try JSONEncoder().encode(filledDraft())
        let restored = try JSONDecoder().decode(OnboardingDraft.self, from: data)
        #expect(restored.quizAnswers.count == 1)
        #expect(restored.quizAnswers.first?.pairID == "p1")
        #expect(restored.quizAnswers.first?.chosenOptionID == "a")
    }

    @Test("An empty draft round-trips without inventing answers")
    func emptyRoundTrips() throws {
        let data = try JSONEncoder().encode(OnboardingDraft())
        let restored = try JSONDecoder().decode(OnboardingDraft.self, from: data)
        #expect(restored.goals.isEmpty)
        #expect(restored.height.state == .unanswered)
        #expect(restored.furthestStepReached == .intro)
    }

    @Test("BodyProfile receives centimetres, never the entered inches")
    func bodyProfileIsMetric() {
        let body = filledDraft().bodyProfile(userID: UUID())
        // 71" -> 180.34cm. A model that stored 71 here is the bug that shipped
        // once already (see BodyProfile's header).
        #expect(abs(body.heightCm! - 180.34) < 0.01)
        #expect(abs(body.chestCm! - 111.76) < 0.01)
        // Declined stays nil rather than becoming zero.
        #expect(body.inseamCm == nil)
    }

    @Test("The derived frame agrees with what was entered")
    func frameDerivesFromDraft() {
        // 44" chest over a 34" waist is a 10" drop — athletic.
        let frame = FrameDerivation.derive(from: filledDraft().bodyProfile(userID: UUID()))
        #expect(frame.taper?.value == .strong)
        // Stated fit issues carry through and outrank derivation.
        #expect(frame.taper?.confidence == 1)  // broadChest override
    }

    @Test("The primary identity is not duplicated into the secondaries")
    func primaryIsNotDuplicated() {
        let style = filledDraft().styleProfile(userID: UUID())
        #expect(style.primaryIdentity == .modernHeritage)
        #expect(!style.secondaryIdentities.contains(.modernHeritage))
        #expect(style.secondaryIdentities.count == 2)
    }

    /// The five fields that could not be persisted until the Phase 2 pre-flight.
    @Test("Every previously-unpersistable field reaches its profile")
    func formerlyDroppedFieldsSurvive() {
        let d = filledDraft()
        let userID = UUID()
        let style = d.styleProfile(userID: userID)
        let lifestyle = d.lifestyleProfile(userID: userID)

        #expect(style.styleGoals.count == 2)
        #expect(lifestyle.currency == "GBP")
        #expect(lifestyle.travelFrequency == "Monthly")
        // §6.8 lists "typical week" as its own field. It had no column and no
        // model property, so the question could not have been asked without
        // dropping the answer.
        #expect(lifestyle.typicalWeek == "Split between home and office")
        #expect(lifestyle.sustainabilityPreference == "Prefer natural fibres")
    }

    /// The §6.7 answers had no route to the database at all: the six properties
    /// existed on the draft, the screen would have written them, and
    /// `bodyProfile(userID:)` dropped every one. Same shape as the coding-key
    /// drift in BodyProfile's header — collected, plausible, never stored.
    @Test("Every appearance answer reaches BodyProfile.appearance")
    func appearanceIsPersisted() {
        var d = filledDraft()
        d.skinUndertone = "Cool"
        d.hairColor = "Salt and pepper"
        d.eyeColor = "Green"
        d.facialHair = "Short beard"
        d.wearsGlasses = true
        d.tattoosVisible = false

        let appearance = d.bodyProfile(userID: UUID()).appearance
        #expect(appearance.skinUndertone == "Cool")
        #expect(appearance.hairColor == "Salt and pepper")
        #expect(appearance.eyeColor == "Green")
        #expect(appearance.facialHair == "Short beard")
        #expect(appearance.wearsGlasses == true)
        // false, not nil — "no visible tattoos" is an answer, and collapsing it
        // to nil would make it indistinguishable from a skipped question.
        #expect(appearance.tattoosVisible == false)
    }

    /// jsonb has no columns, so `check_column_drift.py` cannot police these key
    /// names. Renaming one would silently orphan every value already written.
    @Test("Appearance encodes to the snake_case keys the jsonb column expects")
    func appearanceUsesStorageKeys() throws {
        let appearance = AppearanceProfile(
            skinUndertone: "Warm", wearsGlasses: true, referenceSelfiePaths: ["a/b.jpg"]
        )
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(appearance)
        ) as? [String: Any]
        #expect(json?["skin_undertone"] as? String == "Warm")
        #expect(json?["wears_glasses"] as? Bool == true)
        #expect(json?["reference_selfie_paths"] as? [String] == ["a/b.jpg"])
    }

    @Test("A skipped appearance step is empty rather than a blob of nulls")
    func untouchedAppearanceIsEmpty() {
        #expect(OnboardingDraft().appearanceProfile.isEmpty)
        var d = OnboardingDraft()
        d.wearsGlasses = false
        #expect(!d.appearanceProfile.isEmpty, "answering 'no' is answering")
    }

    @Test("Currency is never lost, so a budget is never ambiguous")
    func budgetCarriesCurrency() {
        let lifestyle = filledDraft().lifestyleProfile(userID: UUID())
        #expect(lifestyle.monthlyBudget == 250)
        // CostPerWearCalculator divides money by wears and shows the result. A
        // budget without a currency is not a rounding error, it is wrong advice.
        #expect(!lifestyle.currency.isEmpty)
    }

    @Test("The completion payload carries all four profiles and the answers")
    func payloadIsComplete() {
        let payload = filledDraft().completionPayload(userID: UUID())
        #expect(payload.styleGoals.count == 2)
        #expect(payload.styleProfile.primaryIdentity == .modernHeritage)
        #expect(payload.bodyProfile.heightCm != nil)
        #expect(payload.lifestyleProfile.currency == "GBP")
        #expect(payload.quizAnswers.count == 1)
    }
}

@Suite("Onboarding — §6.5's exact selection shape")
struct OnboardingIdentityRuleTests {

    @Test("Three selections plus a primary is the only complete state")
    func requiresThreeAndAPrimary() {
        var d = OnboardingDraft()
        #expect(!d.hasCompleteIdentitySelection)

        d.selectedIdentities = [.executive, .minimalist]
        d.primaryIdentity = .executive
        #expect(!d.hasCompleteIdentitySelection, "two selections is not enough")

        d.selectedIdentities = [.executive, .minimalist, .creative]
        d.primaryIdentity = nil
        #expect(!d.hasCompleteIdentitySelection, "three without a primary is not enough")

        d.primaryIdentity = .creative
        #expect(d.hasCompleteIdentitySelection)
    }

    /// Guards the exact bug the view's deselect handler avoids: clearing a
    /// selection without clearing the primary leaves a primary that is not among
    /// the selections, which would block Continue with nothing visibly wrong.
    @Test("A primary outside the selections is not complete")
    func primaryMustBeSelected() {
        var d = OnboardingDraft()
        d.selectedIdentities = [.executive, .minimalist, .creative]
        d.primaryIdentity = .quietLuxury
        #expect(!d.hasCompleteIdentitySelection)
    }
}

@Suite("Onboarding — step sequence and honest progress")
struct OnboardingStepTests {

    @Test("Progress counts only the steps a user answers")
    func progressExcludesIntroAndResult() {
        #expect(!OnboardingStep.answerableSteps.contains(.intro))
        #expect(!OnboardingStep.answerableSteps.contains(.result))
        // Derived rather than hardcoded. A literal count here was wrong on the
        // first run and would have to be edited every time a step is added —
        // which is exactly when the assertion should still hold on its own.
        #expect(OnboardingStep.answerableSteps.count == OnboardingStep.allCases.count - 2)
        #expect(OnboardingStep.intro.answerablePosition == nil)
        #expect(OnboardingStep.result.answerablePosition == nil)
        #expect(OnboardingStep.goals.answerablePosition == 1)
        // The last answerable step must report the final position, or the
        // progress bar never fills and the flow feels unfinished at the end.
        #expect(
            OnboardingStep.answerableSteps.last?.answerablePosition
                == OnboardingStep.answerableSteps.count
        )
    }

    @Test("Only the identity step is required")
    func onlyIdentityIsRequired() {
        for step in OnboardingStep.allCases {
            #expect(step.isSkippable == (step != .identity), "\(step) skippability")
        }
    }

    @Test("The sequence is linear and terminates")
    func sequenceTerminates() {
        var step = OnboardingStep.intro
        var visited = 1
        while let next = step.next {
            step = next
            visited += 1
            #expect(visited <= OnboardingStep.allCases.count, "cycle in the step sequence")
        }
        #expect(step == .result)
        #expect(visited == OnboardingStep.allCases.count)
    }

    @Test("Every step has a rationale, because a form that doesn't say why is abandoned")
    func everyStepExplainsItself() {
        for step in OnboardingStep.allCases {
            #expect(!step.title.isEmpty, "\(step) title")
            #expect(!step.rationale.isEmpty, "\(step) rationale")
        }
    }
}

@Suite("Onboarding — draft store")
struct OnboardingDraftStoreTests {

    @Test("A saved draft comes back")
    func savesAndLoads() async {
        let store = InMemoryOnboardingDraftStore()
        var d = OnboardingDraft()
        d.goals = [.packAndTravelBetter]
        d.furthestStepReached = .measurements

        await store.save(d)
        let loaded = await store.load()
        #expect(loaded?.goals == [.packAndTravelBetter])
        #expect(loaded?.furthestStepReached == .measurements)
    }

    @Test("Clearing removes it")
    func clears() async {
        let store = InMemoryOnboardingDraftStore(draft: OnboardingDraft())
        await store.clear()
        #expect(await store.load() == nil)
    }
}
