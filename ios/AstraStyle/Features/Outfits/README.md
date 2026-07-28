# Outfits

Owns outfit generation, the outfit builder, outfit detail, wear tracking, and the packing assistant (spec §5.4, §6.12, §6.13, §6.24).

## What this module owns

- Outfit generation flow: occasion or natural-language request → 3 ranked outfits with a reason, lock-and-regenerate, visualize, save/schedule/wear/share/shop-missing-items (§5.4).
- Outfit detail (§6.12): hero image, occasion tags, weather range, item strip, "why it works", fit notes, color story, actions, "Complete this look" for missing items.
- Outfit builder (§6.13): flat-lay/mannequin canvas, category rail, tap-to-replace, long-press-to-lock, live compatibility meter, "Ask Kyra to finish", save.
- Occasion management (create/edit/list) backing both the builder and Home's "Upcoming occasions" module.
- Packing assistant (§6.24): destination/dates/activities/dress codes/luggage/laundry access in, packing list + daily outfit plan + rewear map + missing essentials + weather contingencies out.

## Governing spec sections

§5.4 (outfit generation flow), §6.12-§6.13 (screen specs), §6.24 (packing assistant), §9 (`outfits`, `outfit_items`, `outfit_wears`, `occasions`), §10 (Wardrobe Graph compatibility scoring — the live compatibility meter should be backed by `Domain/Services/CompatibilityScoring.swift`), §14 (`POST /outfits/generate`, `POST /outfits/rank`, `POST /packing/generate`).

## What already exists to build against

- `Domain/Repositories/OutfitRepository.swift` — generation, ranking, save/update/delete, wear recording, and packing all live here (packing is grouped with Outfits rather than given its own repository since it's fundamentally a multi-day outfit plan).
- `Domain/Services/CompatibilityScoring.swift` — the exact weighted formula from spec §10, for the builder's live meter.
- `Core/Mocks/MockOutfitRepository.swift` and the sample outfits/items in `Core/Mocks/SampleData.swift`.
- `App/AppRouter.swift` — `OutfitBuilderRoute` and the `HomeRoute` cases Home already pushes into this module's territory (`outfitDetail`, `alternativeLooks`).

## Tickets

Filled in by the **P4-OUTFIT** tickets in `docs/02-task-breakdown.md`.
