# 0016. Women is a second graph, not a gender toggle

## Status

Accepted (2026-08-22). Defers women's taxonomy, quiz catalog, and silhouette
until Wear This is a habit on a real phone. Does **not** amend [0014](0014-account-required-no-guest-mode.md)
or the men's 3-role outfit unit.

## Context

Astra Style's engine unit today is a men's outfit: top / bottom / shoes.
Identity cards (quiet luxury, smart casual, modern heritage), olive as a
neutral, and formality as gym-hoodie to client-meeting are men's craft.
A unisex closet app becomes Indyx with worse photography.

Wave G exists because a women's product on this graph is real work: dresses,
skirts, heel height, occasion dress codes, a second Style DNA quiz catalog,
a second silhouette model, and new empty-state copy. Shipping a gender
field now would make every men's empty state and every scoring prior lie.

## Decision

1. **Do not implement Wave G in this cut.** No women's SKUs in
   `ClothingCategory`, no gender field on Style DNA, no shared quiz pairs,
   no unisex Home.
2. **When it starts**, it is a second product on the same Wardrobe Graph:
   new category enum, new quiz catalog, new silhouette table, new empty
   states. Home for that graph is not men's 3-role copy with a theme switch.
3. **Start only after** A–C are a habit (Wear This changing tomorrow's look
   on a phone) and D–F are live (paste-a-link don't-buy, Studio after
   consent, Discover as his lookbooks).

## Consequences

- Closet, scorer, and first-run stay men's until a dedicated women's
  taxonomy exists.
- Marketing does not grow a women's landing or a "for everyone" line.
- A gender toggle, if it appears in a diff, is a defect — revert it.
