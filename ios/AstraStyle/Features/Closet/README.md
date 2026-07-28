# Closet

Owns the wardrobe browsing/management surface: the Closet tab, category grids, item detail, and closet-level metrics (spec §6.14, §6.15).

## What this module owns

- Closet overview: category tiles, editorial grid / compact list / color spectrum views, filters, search (§6.14).
- Closet metrics: total items, estimated closet value, average cost per wear, most/least worn, versatility.
- Item detail: normalized cutout image, all editable fields, insights (best pairings, outfit gallery, redundancy score, replacement suggestion), and actions (mark worn, add to laundry, edit, archive, sell/donate later) (§6.15).
- Manual item creation/editing (as opposed to the camera capture flow, which belongs to **Scanner**).
- Surfacing the Wardrobe Score composite on the Closet tab (the score itself is computed server-side and consumed via `ClosetRepository.fetchWardrobeScore()`).

## Governing spec sections

§6.14-§6.15 (screen specs), §7 (offline behavior — cached closet remains viewable, edits queue for sync), §9 (`closet_items`, `closet_item_images`), §10 (Wardrobe Graph, Wardrobe Score), §20 (closet grid scrolling at 60fps — use `Core/Utilities/ImageDownsampling.swift`), §21 (empty state copy is specified verbatim: "Add five pieces and Kyra can begin building real outfits.").

## What already exists to build against

- `Domain/Repositories/ClosetRepository.swift` — full CRUD surface plus `WardrobeScore`.
- `Domain/Models/ClosetItem.swift`, `ClosetItemImage.swift`, and every closet-related enum in `Domain/Models/Enums.swift`.
- `Core/Persistence/PersistedClosetItem.swift` + `PersistenceMapping.swift` for the offline cache.
- `Core/Mocks/MockClosetRepository.swift`, seeded from `Core/Mocks/SampleData.swift`'s 25-item sample wardrobe.
- `Core/Utilities/CostPerWearCalculator.swift` and `ImageDownsampling.swift`.

## Tickets

Filled in by the **P3-CLOSET** tickets in `docs/02-task-breakdown.md`.
