# Shopping

Owns the shopping-decision flow: product link analysis, "Shop the look", and the Product Decision Page (spec §5.5, §6.18, §6.19).

## What this module owns

- Product link paste/analysis flow and the resulting compatibility/redundancy/verdict breakdown (§5.5, §6.19).
- "Shop the look" (§6.18): owned-vs-missing item breakdown for an outfit, retailer/price/size display with affiliate disclosure, wishlist, higher/lower-cost alternatives.
- Product Decision Page (§6.19): wardrobe compatibility, new outfits unlocked, redundancy risk, color fit, lifestyle fit, budget fit, expected cost per wear, and Kyra's buy/consider/wait/skip verdict.
- Curated catalog browsing surfaces used both here and from Discover.

## Governing spec sections

§5.5 (shopping decision flow), §6.18-§6.19 (screen specs), §9 (`product_candidates`, `user_product_evaluations`), §10 (purchase unlock count algorithm), §14 (`POST /products/extract`, `POST /products/evaluate`), §17 (affiliate commerce principles — sponsored placement must never change Kyra's verdict), §18 (`product_evaluated`, `affiliate_link_opened`).

## What already exists to build against

- `Domain/Repositories/ShoppingRepository.swift` — extract/evaluate/wishlist/curated catalog.
- `Domain/Models/ProductCandidate.swift` and `ProductEvaluation.swift`.
- `Core/Mocks/MockShoppingRepository.swift` — a small curated catalog (Todd Snyder, Drake's, Alden) plus a believable evaluation verdict.
- Retailer redirects should open via `SFSafariViewController` or a universal link per spec §17 — no in-app web view that could be mistaken for a native checkout.

## Tickets

Filled in by the **P6-SHOP** tickets in `docs/02-task-breakdown.md`.
