# Discover

Owns editorial/educational content: the Discover tab (spec §6.21).

## Status

**His lookbooks, other men's worn public looks, and Unlocks ranked by HIS
gap.** Empty copy is Wear This / paste-a-link. Brand spotlights and a Shop
tab are not this cut.

## What this module owns

- Lookbooks of **his** saved outfits (`DiscoverView` / `DiscoverViewModel` over `OutfitRepository`).
- **Worn by other men** — public + worn, opt-in (ADR 0017).
- **Unlocks** from `ShoppingRepository.fetchUnlocks` (`POST /products/unlocks`): products he already evaluated, `outfitsUnlocked > 0`, ranked by that count. Not `fetchCuratedProducts`.
- Explicitly **not** a shopping feed, not a CMS storefront, not brand spotlights as the first row (founder override of spec §6.21's editorial mall).
- Style guides and brand pages stay placeholders (`DiscoverRoute.styleGuide` / `.brandSpotlight`).

## Governing spec sections

§6.21 named an editorial surface. Wave F is the lookbooks he already owns; P6-CORE-01's CMS table is the trap, not the ticket.

## What already exists to build against

- `Features/Discover/ViewModels/DiscoverViewModel.swift` — lookbooks, public worn looks, Unlocks by gap.
- `Features/Discover/Views/DiscoverView.swift` — rails + empty paste-a-link copy.
- `DiscoverRoute.lookbook` / `.productDecision`. No `curated_content` table.

## Tickets

**P6-CORE-01** (Partial): lookbooks + worn looks + evaluated-gap Unlocks. Do not grow a Shop tab here.
