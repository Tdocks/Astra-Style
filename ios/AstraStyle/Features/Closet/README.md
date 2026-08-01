# Closet

Owns the wardrobe browsing/management surface: the Closet tab, category grids, item detail, and closet-level metrics (spec §6.14, §6.15).

## What this module owns

- Closet overview: category tiles, editorial grid / compact list / color spectrum views, filters, search (§6.14).
- Closet metrics: total items, estimated closet value, average cost per wear, most/least worn, versatility.
- Item detail: normalized cutout image, all editable fields, insights (best pairings, outfit gallery, redundancy score, replacement suggestion), and actions (mark worn, add to laundry, edit, archive, sell/donate later) (§6.15).
- Manual item creation/editing (as opposed to the camera capture flow, which belongs to **Scanner**).
- Surfacing the Wardrobe Score composite on the Closet tab (the score itself is computed server-side and consumed via `ClosetRepository.fetchWardrobeScore()`).

## Governing spec sections

§6.14-§6.15 (screen specs), §7 (offline behavior — cached closet remains viewable, edits queue for sync), §9 (`closet_items`, `closet_item_images`), §10 (Wardrobe Graph, Wardrobe Score), §20 (closet grid scrolling at 60fps — use `Core/Utilities/ImageDownsampling.swift`), §21 (empty state copy is specified verbatim: "Add five pieces and Kyra can begin building real outfits."), §22 (no dead buttons, including in loading/empty/error states).

## What already exists to build against

- `Domain/Repositories/ClosetRepository.swift` — full CRUD surface plus `WardrobeScore`.
- `Domain/Repositories/ClosetImageURLResolving.swift` — signs `user-content` storage paths so a closet surface can actually display a photo. Two methods: one path, or a whole grid's worth in as few round trips as Storage allows.
- `Domain/Models/ClosetItem.swift`, `ClosetItemImage.swift`, and every closet-related enum in `Domain/Models/Enums.swift`.
- `Core/DesignSystem/Components/AstraRemoteImage.swift` (downsampling remote image, deliberately not `AsyncImage`) and `AstraTextField.swift`.
- `Core/Persistence/PersistedClosetItem.swift` + `PersistenceMapping.swift` for the offline cache.
- `Core/Mocks/MockClosetRepository.swift` and `MockClosetImageURLResolver.swift`, seeded from `Core/Mocks/SampleData.swift`'s 25-item sample wardrobe.
- `Core/Utilities/CostPerWearCalculator.swift` and `ImageDownsampling.swift` (`ThumbnailSize.closetGridTile`).

## What is built: the overview screen

The Closet tab's overview and the grid a category tile leads to:

- `ViewModels/ClosetViewModel.swift` — `@Observable`/`@MainActor`, explicit `ViewState`, `isOffline` tracked separately from it, client-side search, per-category counts, and lazy tile-driven image resolution that coalesces a screenful of tiles into ONE signing request. Read its header before changing how images load.
- `Views/ClosetView.swift` — header (My Closet, search, scan), the eight category tiles, and the whole-closet editorial grid.
- `Views/ClosetCategoryView.swift` — the same grid narrowed to one `ClothingCategory`.
- `Components/ClosetCategoryTile.swift`, `ClosetGridTile.swift`, and `ClosetEmptyStateView.swift` (the three empty states, the error state, the offline banner, and the loading skeleton).
- `Routing/ClosetDestinationView.swift` — resolves `ClosetRoute` (defined on `AppRouter`) and is the composition root for every pushed closet screen.
- `Tests/UnitTests/ClosetViewModelTests.swift`.

Three decisions there are load-bearing and are argued at the top of the file that makes them rather than here: why "All items" is a section on the overview instead of a pushed screen (`ClosetView.swift`), why there is no filter button yet (`ClosetView.swift`), and why the tiles ask for their photographs instead of the load pushing them (`ClosetViewModel.swift`).

## Gaps intentionally left for other tickets

- **Metrics row and the three view modes** (total items, estimated value, average cost per wear, most/least worn, versatility; editorial grid / compact list / colour spectrum). The overview is laid out so these slot above and around the all-items grid. `ClosetRoute.colorSpectrum` resolves to a placeholder until then.
- **The filter panel.** `ClosetRoute.filters` exists and resolves to a placeholder, and the overview header deliberately carries no filter control until the panel behind it is real — a control that opens an apology is the dead button spec §22 rules out by name.
- **Item detail** and **the manual add/edit form** are separate tickets. `ClosetDestinationView` already builds `ClosetItemDetailView` for `.itemDetail`.
- **`ClosetRoute.editItem(itemID:)`** is not resolved to the form. The form's editing factory takes a loaded `ClosetItem` and the route carries only an id, so satisfying it means fetching first — which a view may not do. Edit belongs to the item-detail screen, which already holds the item.
- **The scan flow itself.** The closet's scan button calls `AppRouter.startScan()`, which presents the scanner modal; that modal is a placeholder until the Scanner module ships. The control is real and reaches the flow's one entry point — what is behind it is not built yet.
- **Local cache for reads.** `LiveClosetRepository` queues writes offline but does not yet serve reads from `PersistedClosetItem`, so an offline cold start shows the error state rather than a cached closet. The offline banner and the orthogonal `isOffline` flag are already in place for when it does.
