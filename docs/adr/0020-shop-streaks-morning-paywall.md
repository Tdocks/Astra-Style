# 0020. Shop, streaks, and morning-loop paywalls may land (0017-bis)

## Status

Accepted (2026-08-23). **Amends [0017](0017-discover-public-worn-looks.md)**
for later waves. Does **not** add a Shop tab, streaks, or a paywall on
Wear This / Daily Brief / paste-evaluate in this change.

## Context

0017 kept Home private, Discover Unlocks as HIS gap, chrome as Home /
Closet / Discover / Profile, and Wear This / paste-evaluate free. The
still-out program GO’d Shop tab, streaks, and gating the morning loop.

Unlocks (`POST /products/unlocks`) must not become a `last_checked_at`
catalog dump. A Shop tab, if built, is a **separate** surface over
curated `product_candidates` (P6-SHOP-08), not a rename of Discover
Unlocks.

## Decision

1. **Home stays private.** No Open Closet row on Today’s Outfit.
2. **Discover Unlocks stays HIS `computeUnlockCount`.** Zero-unlock rows
   stay off the rail. Sponsored is a label only (P6-SHOP-09). The Shop
   catalog may be **scored** onto that rail; it must not be listed by
   `last_checked_at`.
3. **A Shop tab is permitted as a later wave**, after P6-SHOP-08 ingest
   exists. It is a new `AppTab`, not Discover restyled as a mall.
4. **Streaks are permitted as a later wave.** Wear count is not a streak.
   A streak is a new model and chrome, not a badge on `wear_count`.
5. **Wear This / Daily Brief / paste-evaluate may be gated as a later
   wave**, with **server** 429s (same pattern as Kyra / Studio), not a
   client-only flag. Until that wave, they stay ungated and paywall copy
   still says Wear This is free.
6. **Studio may sit on the dogfood bar** (amends ADR 0015). Visualize
   remains the Home / outfit-detail / Studio-tab generate door.

## Consequences

- Wave 2 is P6-SHOP-08 ingest only.
- Wave 3 is Shop tab + streaks.
- Wave 4 is morning-loop paywalls and must rewrite
  `PaywallViewModel`’s “Wear This stays free” promise in the same change
  as the server gates.
- Public TestFlight remains a later owner-machine cut, not this ADR.
