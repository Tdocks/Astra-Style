# Closet

Owns the wardrobe browsing/management surface: the Closet tab, category grids, item detail, and closet-level metrics (spec §6.14, §6.15).

## What this module owns

- Closet overview: category tiles, editorial grid / compact list / color spectrum views, filters, search (§6.14).
- Closet metrics: total items, estimated closet value, average cost per wear, most/least worn (versatility is deliberately absent — Phase 4 inputs).
- Item detail: image, editable fields, actions (mark worn, edit, archive) (§6.15). Insights that need the Wardrobe Graph (best pairings, redundancy, replacement) are not wired yet.
- Manual item creation/editing (as opposed to the camera capture flow, which belongs to **Scanner**).
- Surfacing the Wardrobe Score composite on the Closet tab when a server implementation exists (`ClosetRepository.fetchWardrobeScore()` currently throws `unimplemented`; the overview deliberately never calls it).

## Governing spec sections

§6.14-§6.15 (screen specs), §7 (offline behavior — cached closet remains viewable, edits queue for sync), §9 (`closet_items`, `closet_item_images`), §10 (Wardrobe Graph, Wardrobe Score), §20 (closet grid scrolling at 60fps — use `Core/Utilities/ImageDownsampling.swift`), §21 (empty state copy is specified verbatim: "Add five pieces and Kyra can begin building real outfits."), §22 (no dead buttons, including in loading/empty/error states).

## What is built

- `ViewModels/ClosetViewModel.swift` — `@Observable`/`@MainActor`, explicit `ViewState`, `isOffline` tracked separately, client-side search, per-category counts, lazy tile-driven image resolution. Read its header before changing how images load.
- `Views/ClosetView.swift`, `Views/ClosetCategoryView.swift` — overview and category-narrowed grids.
- `Views/ClosetItemDetailView.swift` + form views for manual add/edit.
- Metrics row (`ClosetMetrics` / `ClosetMetricsRow`) — five of six §6.14 metrics; versatility omitted honestly.
- Three view modes (`ClosetViewMode`: editorial grid, compact list, colour spectrum) persisted at `@AppStorage("closet.viewMode")`.
- Filter panel as a **sheet** (eight facets; OR within a facet, AND across facets). See `ClosetFilters`.
- Empty-state precedence via `emptyReason(for:)` — do not reorder without reading the bugs it encodes.
- `Routing/ClosetDestinationView.swift`, components, and unit tests under `Tests/UnitTests/Closet*`.

Domain seams this module builds on: `ClosetRepository`, `ClosetImageURLResolving`, closet models/enums, `AstraRemoteImage`, `AstraTextField`, SwiftData persistence mapping, mocks + sample wardrobe, `CostPerWearCalculator`, `ImageDownsampling`.

## Gaps still open

- **The scan flow itself.** The closet's scan button reaches `AppRouter.startScan()`. Guests are gated before the modal opens. The scanner modal behind that entry point is still a placeholder until Scanner ships UI.
- **Local cache for reads.** `LiveClosetRepository` queues writes offline but does not yet serve reads from `PersistedClosetItem`, so an authenticated offline cold start shows the error state rather than a cached closet.
- **Free-tier 30-item cap** — only the guest 10-item cap exists today.
- **§6.15 insights** that need outfit/graph data (best pairings, redundancy, replacement).
- **Dead route cases.** `ClosetRoute.filters` and `ClosetRoute.editItem` resolve to honest placeholders and nothing pushes them (filters are a sheet; edit is presented from detail with a loaded item). Do not wire them to the wrong thing on the assumption they are wanted.
- **Wardrobe Score** — no `wardrobe_scores` table / scorer; the overview must not call `fetchWardrobeScore()` until one exists.
