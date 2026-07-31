# Onboarding

Owns first-launch, sign-in, and the full onboarding flow that produces a new user's Style DNA (spec §5.1, §6.2-§6.10).

## What this module owns

- Splash routing hand-off, Welcome/authentication (Sign in with Apple, email OTP, guest mode) — note a minimal placeholder version of this screen currently lives in `App/RootView.swift` (`SignedOutGateView`) purely so the app has something to show for `AppRouteState.signedOut`; this module should absorb and replace it.
- Kyra introduction (§6.3).
- Style goals multi-select (§6.4).
- Style identity card selection (§6.5).
- Measurements and fit (§6.6).
- Appearance profile (§6.7) — note: spec §9's data model has no dedicated table for appearance fields; §6.6's `BodyProfile.fitNotes` is the closest persisted home for anything collected here until the schema is extended (see the top-level README's "spec ambiguities" section).
- Lifestyle profile (§6.8).
- Style preference visual quiz (§6.9).
- Optional selfie/body reference capture (§5.1 step 11) — no §6.x screen section of its own, so
  its brief is §29 (informed consent before collection, honest disclosure, deletion) plus ADR 0010
  (private bucket, `users/{user_id}/references/...`, retention) and ADR 0011 (a guest's photo never
  leaves the device). The consent copy stands alone rather than linking out, because
  `AstraLegal.isPublished` is `false` and every document URL is `nil`. Nothing is uploaded at
  capture time — see `OnboardingViewModel.uploadReferenceImageIfNeeded()`.
- Add first closet items, or skip (§5.1 step 12) — writes real `closet_items` rows through
  `ClosetRepository`, so a guest's stay local behind the §6.2 ten-item cap. Deliberately a
  three-field form; `P3-CLOSET-08` owns the full editor, and nothing here depends on the scanner.
- Style DNA result + edit/regenerate (§6.10).
- Guest-to-account migration (spec §7).

## Governing spec sections

§5.1 (first-launch flow), §6.2-§6.10 (screen specs), §7 (authentication, guest migration), §9 (`profiles`, `style_profiles`, `body_profiles`, `lifestyle_profiles`), §14 (`POST /profile/complete-onboarding`, `POST /style-dna/generate`), §16 (paywall may appear at the end of onboarding), §23 (MVP scope — onboarding + Style DNA is a "must ship").

## What already exists to build against

- `Domain/Repositories/ProfileRepository.swift` — `completeOnboarding(_:)` and `generateStyleDNA()`, plus `OnboardingCompletionPayload` and `StylePreferenceQuizAnswer`.
- `Domain/Models/Enums.swift` — `StyleIdentity` (the ten identities in §6.5), `FormalityLevel`, `ToleranceLevel`, `AccessoryPreference`, `FitIssue`, `OccupationCategory`, `DressCode`, `LaundryCadence`.
- `Core/Mocks/MockProfileRepository.swift` and `Core/Mocks/SampleData.swift` for previews.
- `App/AppRouter.swift` — `AppRouteState.onboarding` is already wired into `RootView`; this module supplies the real multi-step flow that replaces `OnboardingPlaceholderView`.

## Tickets

Filled in by the **P2-ONBOARD** tickets in `docs/02-task-breakdown.md`.
