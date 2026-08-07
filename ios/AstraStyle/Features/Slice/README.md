# Features/Slice — temporary scaffolding, not product code

**This module is throwaway.** It exists to validate the architecture end to
end before the rest of Phase 1 and Phase 2 are built (see
`docs/01-build-roadmap.md` §"Vertical slice first"), and it is expected to
be **deleted once Phases 1–4 land** and the real five-tab app (Home,
Closet, Studio, Discover, Profile — `App/MainTabView.swift`) grows its own
sign-in, closet, and outfit-generation screens. Do not:

- extend this screen with new features,
- treat `SliceView`/`SliceViewModel` as a reference implementation to copy
  wholesale into a real feature module (skim it for the auth/nonce/Edge
  Function-call patterns, but rebuild the UI properly against the design
  system and the real navigation/state architecture),
- wire it into anything user-facing / ship it active in a Release build.

## What it proves

Per the roadmap, this slice retires four specific architectural risks by
exercising them against a **real** Supabase project and a **real** deployed
Edge Function — not mocks:

1. Supabase Auth + Row Level Security actually protects a real signed-in
   user's data end to end (not just in isolated policy tests).
2. A client write (`closet_items` insert) round-trips correctly through
   Postgrest against the real schema.
3. An Edge Function (`outfits/generate`) can be deployed, JWT-validated,
   and called from the client without a service-role key ever touching the
   app bundle.
4. The `closet_items` → `outfit_items` → `outfit_wears` data shape (and its
   `bump_closet_item_wear_stats` trigger) is workable once real code is
   written against it.

## The flow

Sign in with Apple → add one garment (manual form: name, category, primary
color — no camera/Vision/segmentation) → tap **Generate Outfit** (calls the
real `POST /outfits/generate` Edge Function) → the returned outfit is
displayed, resolved against the closet items already in memory → **Mark
Worn** writes a real `outfit_wears` row.

## What's explicitly excluded (do not add these here)

Style DNA / onboarding, camera/OCR, Kyra, Style Studio, product evaluation,
notifications, StoreKit, account deletion, and any design
polish beyond the existing `Astra*` tokens. If a task asks for any of
these, it belongs in the real feature module under `Features/`, not here.

## How it's wired in

`RootView` shows `SliceRootView` instead of the normal `AppRouteState`
flow when `AstraFeatureFlags.verticalSliceEnabled` is `true`
(`Core/Utilities/AstraFeatureFlags.swift`) — a `#if DEBUG`-gated check of
the `ASTRA_VERTICAL_SLICE` environment variable, so it can never be active
in a Release build and never touches `AppRouteState`'s meaning for the real
app. Enable it via Xcode: Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments ▸
Environment Variables ▸ `ASTRA_VERTICAL_SLICE = 1`.

## Files

- `SliceView.swift` — the one screen (`SliceRootView` builds the view model
  from `AppContainer`; `SliceView` is the actual UI, driven entirely by
  `SliceViewModel`'s published state).
- `SliceViewModel.swift` — `@Observable`, `@MainActor`, talks only to
  `Domain/Repositories` protocols (`AuthRepository`, `ClosetRepository`,
  `OutfitRepository`) and `AppleSignInProviding` (Core/Auth). No networking
  in this file or in the view (CLAUDE.md "No network calls in views").

## Schema notes for whoever touches this next

- `closet_items` here uses only `name`, `category`, `primary_color` — every
  other column is left at its default, matching the roadmap's "minimal
  columns" scope for the slice.
- **`wear_count` lives on `closet_items`, not `outfits`** — there is no
  `outfits.wear_count` column. `outfit_wears` insert triggers
  `bump_closet_item_wear_stats()` (see
  `supabase/migrations/20260728101200_functions_and_triggers.sql`), which
  increments `wear_count`/`last_worn_at` on every owned `closet_item` in
  that outfit. `SliceViewModel.markWorn()` only inserts the `outfit_wears`
  row — it does **not** separately increment anything client-side. Adding
  client-side incrementing here would double-count against the trigger.
