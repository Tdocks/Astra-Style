# Home

Owns Kyra's Daily Brief — the Home tab and the app's default landing screen after onboarding (spec §6.11, §4, §5.2 "Daily use").

## What this module owns

- Kyra's daily outfit, the measured reason behind it, Wear This / Something Else / Edit / Visualize actions, current weather, the seven-day plan, and the closet-aware empty state.
- Loading (skeleton), loaded, empty, offline, and recoverable-error states, per spec §21.
- Wardrobe-level metrics and history live in Closet and Profile so Home stays focused on today's outfit.

## Status

**The daily outfit path is implemented**, not scaffolded — it is the reference implementation the other feature modules are patterned after. See:

- `ViewModels/HomeViewModel.swift` — `@Observable`/`@MainActor`, explicit `ViewState`, zero direct repository access.
- `Services/HomeBriefProviding.swift` — the single protocol the view model depends on; `DefaultHomeBriefProvider` composes `OutfitRepository` + `ProfileRepository` + `ClosetRepository` + `WeatherService` + `CalendarService`.
- `Views/HomeView.swift` — no network calls in the view (spec §8); drives entirely off `HomeViewModel.state`.
- `Components/` — one file per visual module, each independently previewable.
- `Routing/HomeDestinationView.swift` — resolves `HomeRoute` (defined on `AppRouter`) to a destination view; most destinations are `FeaturePlaceholderView`s pending the owning module below.

## Governing spec sections

§4 (tab bar / navigation model), §5.2 (daily use flow), §6.11 (screen spec), §7 (offline behavior), §8 (architecture/state rules), §9 (`daily_briefs` data model), §14 (`POST /daily-brief/generate`), §20 (performance targets — cached render < 500ms), §21 (error/empty states), §22 (testing requirements).

## Open destinations and planned work

- The "Purchase opportunity" module renders when `HomeBriefData.purchaseOpportunity` is populated, but `DefaultHomeBriefProvider` never populates it yet — that requires `ShoppingRepository` integration and belongs to **P6-SHOP**.
- The Monthly Review destination reads this month's closet additions, tracked spend, wear history, product evaluations, underused pieces, and Wardrobe Score. On first use it saves an RLS-protected versatility baseline; later months show the recorded change. The view can hand the recorded facts to Kyra for a written reflection.
- Alternative looks, the Kyra thread, and occasion detail also resolve to placeholders in `HomeDestinationView.swift`.
- Notifications and their in-context permission timing are **P7-HOME-01/02**.
