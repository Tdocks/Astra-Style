//
//  MockProfileRepository.swift
//  AstraStyle
//
//  In-memory `ProfileRepository` for previews/tests, seeded from
//  `SampleData` (spec §31).
//

import Foundation

public actor MockProfileRepository: ProfileRepository {
    private var profile: Profile
    private var styleProfile: StyleProfile?
    private var bodyProfile: BodyProfile?
    private var lifestyleProfile: LifestyleProfile?

    public init(
        profile: Profile = SampleData.profile,
        styleProfile: StyleProfile? = SampleData.styleProfile,
        bodyProfile: BodyProfile? = SampleData.bodyProfile,
        lifestyleProfile: LifestyleProfile? = SampleData.lifestyleProfile
    ) {
        self.profile = profile
        self.styleProfile = styleProfile
        self.bodyProfile = bodyProfile
        self.lifestyleProfile = lifestyleProfile
    }

    public func fetchCurrentProfile() async throws -> Profile { profile }

    public func updateProfile(_ profile: Profile) async throws -> Profile {
        self.profile = profile
        return profile
    }

    public func fetchStyleProfile() async throws -> StyleProfile? { styleProfile }

    public func updateStyleProfile(_ styleProfile: StyleProfile) async throws -> StyleProfile {
        self.styleProfile = styleProfile
        return styleProfile
    }

    public func fetchBodyProfile() async throws -> BodyProfile? { bodyProfile }

    public func updateBodyProfile(_ bodyProfile: BodyProfile) async throws -> BodyProfile {
        self.bodyProfile = bodyProfile
        return bodyProfile
    }

    public func fetchLifestyleProfile() async throws -> LifestyleProfile? { lifestyleProfile }

    public func updateLifestyleProfile(_ lifestyleProfile: LifestyleProfile) async throws -> LifestyleProfile {
        self.lifestyleProfile = lifestyleProfile
        return lifestyleProfile
    }

    public func completeOnboarding(_ payload: OnboardingCompletionPayload) async throws -> Profile {
        styleProfile = payload.styleProfile
        bodyProfile = payload.bodyProfile
        lifestyleProfile = payload.lifestyleProfile
        profile.onboardingCompletedAt = .now
        return profile
    }

    public func generateStyleDNA() async throws -> StyleProfile {
        styleProfile ?? SampleData.styleProfile
    }

    public func exportPersonalData() async throws -> URL {
        URL(string: "https://example.com/preview-export.json") ?? URL(fileURLWithPath: "/preview-export.json")
    }
}
