//
//  ProfileRepository.swift
//  AstraStyle
//
//  Owns `profiles`, `style_profiles`, `body_profiles`, and
//  `lifestyle_profiles` (spec §9), plus the onboarding-completion and
//  Style DNA generation orchestration calls (spec §14).
//

import Foundation

public protocol ProfileRepository: Sendable {
    func fetchCurrentProfile() async throws -> Profile
    func updateProfile(_ profile: Profile) async throws -> Profile

    func fetchStyleProfile() async throws -> StyleProfile?
    func updateStyleProfile(_ styleProfile: StyleProfile) async throws -> StyleProfile

    func fetchBodyProfile() async throws -> BodyProfile?
    func updateBodyProfile(_ bodyProfile: BodyProfile) async throws -> BodyProfile

    func fetchLifestyleProfile() async throws -> LifestyleProfile?
    func updateLifestyleProfile(_ lifestyleProfile: LifestyleProfile) async throws -> LifestyleProfile

    /// Finalizes onboarding (spec §5.1 steps 6-13): submits the collected
    /// goals/identity/measurements/appearance/lifestyle/quiz answers in one
    /// call so the server can generate the initial Style DNA atomically.
    /// Calls `POST /profile/complete-onboarding`.
    func completeOnboarding(_ payload: OnboardingCompletionPayload) async throws -> Profile

    /// Regenerates Style DNA from the current profile state (spec §6.10
    /// "Allow user to edit and regenerate"). Calls `POST /style-dna/generate`.
    func generateStyleDNA() async throws -> StyleProfile

    /// Exports all personal data (spec §29 "Export personal data").
    func exportPersonalData() async throws -> URL
}

/// Everything collected across the onboarding flow (spec §6.4-§6.9),
/// submitted together to `POST /profile/complete-onboarding`.
public struct OnboardingCompletionPayload: Encodable, Sendable {
    public var styleGoals: [String]
    public var styleProfile: StyleProfile
    public var bodyProfile: BodyProfile
    public var lifestyleProfile: LifestyleProfile
    public var quizAnswers: [StylePreferenceQuizAnswer]

    public init(
        styleGoals: [String],
        styleProfile: StyleProfile,
        bodyProfile: BodyProfile,
        lifestyleProfile: LifestyleProfile,
        quizAnswers: [StylePreferenceQuizAnswer]
    ) {
        self.styleGoals = styleGoals
        self.styleProfile = styleProfile
        self.bodyProfile = bodyProfile
        self.lifestyleProfile = lifestyleProfile
        self.quizAnswers = quizAnswers
    }

    enum CodingKeys: String, CodingKey {
        case styleGoals = "style_goals"
        case styleProfile = "style_profile"
        case bodyProfile = "body_profile"
        case lifestyleProfile = "lifestyle_profile"
        case quizAnswers = "quiz_answers"
    }
}

/// One paired-image comparison answer from spec §6.9's preference quiz.
///
/// `Codable` and `Hashable`, not merely `Encodable`. It began as an
/// encode-only submission payload, but the onboarding draft holds these while
/// the user works through the quiz and has to persist locally between launches
/// — which needs decoding — and be `Hashable` so the draft itself can be. A
/// mirror type was written to work around that and then deleted: two shapes for
/// one concept is how they drift.
public struct StylePreferenceQuizAnswer: Codable, Hashable, Sendable {
    public var pairID: String
    public var chosenOptionID: String

    public init(pairID: String, chosenOptionID: String) {
        self.pairID = pairID
        self.chosenOptionID = chosenOptionID
    }

    enum CodingKeys: String, CodingKey {
        case pairID = "pair_id"
        case chosenOptionID = "chosen_option_id"
    }
}
