# 0015. First-run is a taste snapshot, not the full Style DNA wall

## Status

Accepted (2026-08-22). Amends spec §4 (tab chrome for dogfood), §5.1
(first-launch sequence), and §6.9 (how many comparisons the front door asks).
Does **not** touch [0014](0014-account-required-no-guest-mode.md): an account
is still required before any onboarding step.

## Context

Internal TestFlight 1.0.0 (1) made the founder wait through the full §6.3–§6.10
wall — identity, measurements, appearance, lifestyle, an eight-axis paired-image
quiz, optional reference photo, then first closet items — before Home's
Today's Outfit. Simulator capture after Style DNA showed the dogfood loop
already working (Home, Closet, Scan One Piece) while Studio and Discover sat
in the tab bar as "Not built yet".

The uninstall reading is bait-and-switch: homework, then two unfinished tabs,
then the outfit. The north star is decision compression on clothes you already
own, not a catalog. Anything in the front door that does not change Daily Brief
in week 1 is deferred, not deleted.

## Decision

1. **First-run sequence is** intro → identity (required) → taste-snapshot quiz
   (at most three comparisons) → photo-first first items (skippable) → Style
   DNA result → Home. Account required before this, per ADR 0014.
2. **Deferred from the front door, not deleted:** goals, measurements,
   appearance, lifestyle, reference selfie, remaining quiz axes (including
   `silhouette`, which ships at one pair and cannot rise above `.low`
   confidence). Screens and persistence stay. They may be asked later from
   Profile / Home once the closet has signal. `-astra-full-onboarding` (Debug)
   still walks the old sequence so consent-gate tests keep a path to the
   reference step.
3. **The quiz catalog remains 12–20 pairs.** First-run asks at most three,
   ordered for coverage, dropping pairs that only probe deferred axes. Sparse
   vectors are already a first-class Style DNA input; absent > fake.
4. **Tab chrome for this cut is Home, Closet, Profile.** Studio and Discover
   stay in `AppTab` and keep their placeholder screens, but they are not in
   the tab bar until they serve the Wardrobe Graph. A Debug flag
   `-astra-show-unfinished-chrome` restores them for QA. Visualize / "see it
   on you" is the same unfinished surface and is hidden with them.
5. **Profile shows About** with the marketing version and build number so
   dogfood can tell binaries apart. It does not grow a stats dashboard
   (`P7-HOME-05`).

## Amendment (2026-08-22, Waves E–F)

Discover now lists his saved outfits as lookbooks, so it **joins** the
dogfood bar: Home, Closet, Discover, Profile. Studio stays **off** the bar.
The generate door is Visualize / See this on you, after terms-versioned
consent — not a Studio tab, not a preset mall. Women remains out of chrome
entirely; see [0016](0016-women-is-a-second-graph.md).

## Consequences

- `OnboardingStep.next` / `.previous` / progress follow `activeSequence`, not
  `allCases`. Old drafts parked on a deferred step clamp forward to the next
  first-run step.
- Skip on first items still reaches an honest Home empty state. The empty
  state's job is "scan a piece → Wear This", not a second homework wall.
- Marketing copy on astra-style.com must match this chrome: Closet → Today's
  Outfit → Wear This. No Studio/Discover screenshots, no versatility theater.
- Public TestFlight / Submit stay blocked until this cut is the binary being
  dogfooded. Crossed Out stays watch-only.
