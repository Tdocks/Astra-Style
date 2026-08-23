# 0017. Discover may show worn public looks; Home stays private

## Status

Accepted (2026-08-22). Amends the Wave F “his lookbooks only” line in
[0015](0015-first-run-taste-snapshot.md) without undoing men’s 3-role
scoring or [0016](0016-women-is-a-second-graph.md).

## Context

Wave F put Discover on the dogfood bar as **his** saved outfits. The
growth leftover plan reopens two kill-list items on Discover only:
other men’s **worn** looks (opt-in, never auto-published) and an
**Unlocks** product rail from `product_candidates` that fill *his*
gaps. Home remains Today’s Outfit → Wear This. A follow graph, a Shop
tab, and sponsored sort stay out.

Empty public social is worse than none: the empty rail says “Wear This,
then make a look public,” not a barren feed.

## Decision

1. **Home stays private.** No row of strangers on Today’s Outfit.
2. **Discover may list** (a) his lookbooks, (b) other men’s public worn
   looks, (c) Unlocks — products **he already evaluated**, re-scored
   against **his** closet, ranked by `computeUnlockCount` (gap > 0).
   Never a `last_checked_at` catalog dump, never sponsored sort
   (P6-SHOP-09). Chrome stays Home / Closet / Discover / Profile. Studio
   stays off the bar.
3. **`outfits.visibility`** defaults to `private`. Public requires a
   wear and an explicit opt-in (outfit detail or post–Wear This on Home).
4. **Report stub** (`lookbook_reports`) so public looks are not an
   unmoderated mall.
5. **Wear This stays free.** Kyra’s 3/day new-thread cap and Studio’s
   one Visualize trial present the existing paywall; paste-evaluate and
   the morning loop do not.

## Consequences

- RLS on `outfits` remains owner-write. Authenticated SELECT of
  `visibility = public` AND worn AND not archived is additive; default
  private rows stay isolated.
- Marketing still must not screenshot Open Closet tourism as Home.
- **Amendment (2026-08-22):** week-strip and packing are GO’d. Home stays
  one look; the seven-day strip sits under Wear This. Packing is
  `POST /packing/generate` over the same scorer, not a second engine.
  Paid image gen, a Shop tab, streaks, guest, and women’s chrome stay out.
- **Amendment (2026-08-22, Unlocks):** Discover Unlocks is
  `POST /products/unlocks` — HIS evaluated gaps via `computeUnlockCount`,
  not `product_candidates` ordered by `last_checked_at`. Zero-unlock rows
  never appear. Sponsored is a label only.
- **Amendment (2026-08-23, catalog Unlocks):** Discover Unlocks may score
  shared `product_candidates` (the Shop catalog) with `computeUnlockCount`
  in addition to paste-evaluations. Zero-unlock rows still never appear.
  Ranking is still gap, never `last_checked_at`. Studio may sit on the
  dogfood bar; see [0015](0015-first-run-taste-snapshot.md).
