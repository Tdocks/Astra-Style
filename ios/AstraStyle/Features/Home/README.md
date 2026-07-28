# Home

Owns Kyra's Daily Brief — the Home tab and the app's default landing screen after onboarding (spec §6.11, §4, §5.2 "Daily use").

## What this module owns

- The Daily Brief header (greeting, weather, schedule summary), hero outfit card, and every secondary module listed in spec §6.11 (alternative looks, Wardrobe Score, Kyra's Insight, purchase opportunity, upcoming occasions, laundry alert, monthly progress).
- The empty state prompting a new user to add their first five closet items.
- Loading (skeleton), loaded, empty, offline, and recoverable-error states, per spec §21.

## Status

**This module is fully implemented**, not scaffolded — it is the reference implementation the other feature modules are patterned after. See:

- `ViewModels/HomeViewModel.swift` — `@Observable`/`@MainActor`, explicit `ViewState`, zero direct repository access.
- `Services/HomeBriefProviding.swift` — the single protocol the view model depends on; `DefaultHomeBriefProvider` composes `OutfitRepository` + `ProfileRepository` + `ClosetRepository` + `WeatherService` + `CalendarService`.
- `Views/HomeView.swift` — no network calls in the view (spec §8); drives entirely off `HomeViewModel.state`.
- `Components/` — one file per visual module, each independently previewable.
- `Routing/HomeDestinationView.swift` — resolves `HomeRoute` (defined on `AppRouter`) to a destination view; most destinations are `FeaturePlaceholderView`s pending the owning module below.

## Governing spec sections

§4 (tab bar / navigation model), §5.2 (daily use flow), §6.11 (screen spec), §7 (offline behavior), §8 (architecture/state rules), §9 (`daily_briefs` data model), §14 (`POST /daily-brief/generate`), §20 (performance targets — cached render < 500ms), §21 (error/empty states), §22 (testing requirements).

## Gaps intentionally left for other tickets

- The "Purchase opportunity" module renders when `HomeBriefData.purchaseOpportunity` is populated, but `DefaultHomeBriefProvider` never populates it yet — that requires `ShoppingRepository` integration and belongs to **P6-SHOP**.
- `MonthlyProgressModuleView` exists and is previewable but isn't wired into `HomeView` yet — it needs monthly wear/spend aggregation, which is Style Journey's concern (**P7-SUB**).
- Every non-Home destination reached from `HomeRoute` (outfit detail, alternatives list, Kyra thread, occasion detail, monthly review, product decision) currently resolves to a `FeaturePlaceholderView` — see `HomeDestinationView.swift` for exactly which ticket owns each (**P4-OUTFIT**, **P5-KYRA**, **P6-SHOP**, **P7-SUB**).
