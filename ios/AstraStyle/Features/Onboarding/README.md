# Onboarding

Owns first-launch, sign-in, and the full onboarding flow that produces a new user's Style DNA (spec §5.1, §6.2-§6.10).

## What this module owns

- Splash routing hand-off, Welcome/authentication (Sign in with Apple, email OTP — an account is required, ADR 0014) — note a minimal placeholder version of this screen currently lives in `App/RootView.swift` (`SignedOutGateView`) purely so the app has something to show for `AppRouteState.signedOut`; this module should absorb and replace it.
- Kyra introduction (§6.3).
- Style identity card selection (§6.5) — the one required first-run answer.
- Taste-snapshot visual quiz (§6.9, ADR 0015) — at most three comparisons; remaining axes deferred.
- Add first closet items, photo-first, or skip (§5.1) — writes real `closet_items` rows through
  `ClosetRepository`, behind spec §16's free-tier cap.
- Style DNA result + edit/regenerate (§6.10).

Deferred from first-run (screens still exist; `-astra-full-onboarding` walks them in Debug):
goals (§6.4), measurements (§6.6), appearance (§6.7), lifestyle (§6.8), optional reference
capture. An account is required before any of this (ADR 0014).

## Governing spec sections

§5.1 (first-launch flow), §6.2-§6.10 (screen specs), §7 (authentication), §9 (`profiles`, `style_profiles`, `body_profiles`, `lifestyle_profiles`), §14 (`POST /profile/complete-onboarding`, `POST /style-dna/generate`), §16 (paywall may appear at the end of onboarding), §23 (MVP scope — onboarding + Style DNA is a "must ship").

## What already exists to build against

- `Domain/Repositories/ProfileRepository.swift` — `completeOnboarding(_:)` and `generateStyleDNA()`, plus `OnboardingCompletionPayload` and `StylePreferenceQuizAnswer`.
- `Domain/Models/Enums.swift` — `StyleIdentity` (the ten identities in §6.5), `FormalityLevel`, `ToleranceLevel`, `AccessoryPreference`, `FitIssue`, `OccupationCategory`, `DressCode`, `LaundryCadence`.
- `Core/Mocks/MockProfileRepository.swift` and `Core/Mocks/SampleData.swift` for previews.
- `App/AppRouter.swift` — `AppRouteState.onboarding` is already wired into `RootView`; this module supplies the real multi-step flow that replaces `OnboardingPlaceholderView`.

## Tickets

Filled in by the **P2-ONBOARD** tickets in `docs/02-task-breakdown.md`.
