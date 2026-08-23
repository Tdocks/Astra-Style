# 0019. Wave G may start (0016-bis)

## Status

Accepted (2026-08-23). **Amends [0016](0016-women-is-a-second-graph.md)**
to allow Wave G as a later wave. Does **not** add women’s SKUs, quiz
pairs, or chrome in this change.

## Context

0016 deferred women’s taxonomy until Wear This is a habit on a phone and
Waves D–F are live. D–F are live (paste-evaluate, Visualize consent,
Discover lookbooks + Unlocks). Wear This on a physical iPhone is in
progress (internal TestFlight / Debug), not yet a proven habit.

The still-out program GO’d women’s chrome anyway. 0016’s shape still
binds: this is a **second graph**, not a gender toggle on men’s Home.

## Decision

1. **A gender toggle remains a defect.** Revert it if it appears.
2. **Wave G is permitted to start as its own wave**, not as a theme switch.
   Required when it starts: new `ClothingCategory` values, a second Style
   DNA quiz catalog, a second silhouette model, and empty-state copy that
   is not men’s 3-role text.
3. **Men’s Home, Closet, Discover, and scoring stay the current graph**
   until that wave ships. Unlocks ranking (`computeUnlockCount` on HIS
   evaluations) is unchanged.

## Consequences

- Wave 6 of the still-out program is the implementation slice (size L+).
- Marketing still must not claim “for everyone” on the men’s graph.
- 0016’s “start only after habit” criterion is waived as a gate; the
  second-graph requirement is not.
