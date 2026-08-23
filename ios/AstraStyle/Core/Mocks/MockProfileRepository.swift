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

    public func generateStyleDNA() async throws -> StyleDNA {
        var generated = SampleData.styleDNA

        // The identity is READ BACK from the stored row rather than fixed to
        // the fixture's. The real endpoint derives everything from that row, so
        // a mock that returned the same document no matter what was written
        // could not show the one behaviour §6.10's "edit and regenerate" is
        // judged on: a user changes his answer, regenerates, and the result
        // changes.
        //
        // Only the identity moves. The palette, silhouette, signatures and
        // priorities stay the fixture's — deriving ten of each here would be a
        // second copy of `identityPlaybook.ts` living in the app target, and it
        // would drift from the server's the first time either was retuned. The
        // fixture's prose does NAME its identity in two places, though, so the
        // name is substituted along with it: a preview whose headline says one
        // direction while the paragraph under it says another is a screen that
        // contradicts itself, which is worse to look at than one that does not
        // reflect the edit at all.
        if let primary = styleProfile?.primaryIdentity {
            generated.primaryIdentity = primary
            generated.secondaryInfluences = styleProfile?.secondaryIdentities ?? []
            if let fixtureName = SampleData.styleDNA.primaryIdentity?.displayName,
               fixtureName != primary.displayName {
                generated.summary = generated.summary
                    .replacingOccurrences(of: fixtureName, with: primary.displayName)
                generated.palette.rationale = generated.palette.rationale
                    .replacingOccurrences(of: fixtureName, with: primary.displayName)
            }
        }

        // Mirrors what the Edge Function does after generating: the four
        // §6.10 summary columns, the palette and the written summary are
        // written back onto the stored style profile, and the user's own
        // answers (identity, goals, fit, the §6.9 vector) are left untouched.
        // Without this, a preview that regenerated would show a new Style DNA
        // beside a stale profile — a disagreement the real backend does not
        // have.
        if let styleProfile {
            self.styleProfile = generated.applyingSummary(to: styleProfile)
        }
        return generated
    }

    /// Returns a path in the §15 shape rather than a placeholder string, so
    /// anything that later parses the `users/{uid}/references/` convention
    /// behaves the same against the mock as against Supabase.
    public func uploadReferenceImage(_ imageData: Data) async throws -> String {
        "users/\(UUID().uuidString.lowercased())/references/\(UUID().uuidString.lowercased()).jpg"
    }

    public func exportPersonalData() async throws -> URL {
        URL(string: "https://example.com/preview-export.json") ?? URL(fileURLWithPath: "/preview-export.json")
    }

    public func applyReferralCode(_ code: String) async throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AstraError.validation("Enter a code.")
        }
        profile.referredBy = profile.referredBy ?? UUID()
    }
}
