# Discover

Owns editorial/educational content: the Discover tab (spec §6.21).

## Status

**Wave F lists his saved outfits as lookbooks.** Empty copy is "Wear This or
save a look first." Brand spotlights and shopping feeds are not this cut.

## What this module owns

- Lookbooks of **his** saved outfits (`DiscoverView` / `DiscoverViewModel` over `OutfitRepository`).
- Explicitly **not** a shopping feed, not a CMS storefront, not brand spotlights as the first row (founder override of spec §6.21's editorial mall).
- Style guides and brand pages stay placeholders (`DiscoverRoute.styleGuide` / `.brandSpotlight`).

## Governing spec sections

§6.21 named an editorial surface. Wave F is the lookbooks he already owns; P6-CORE-01's CMS table is the trap, not the ticket.

## What already exists to build against

- `Features/Discover/ViewModels/DiscoverViewModel.swift` — `fetchOutfits()`, drop archived, honest empty.
- `Features/Discover/Views/DiscoverView.swift` — list + empty copy, no product cards.
- `DiscoverRoute.lookbook` pushes `OutfitDetailView`. No `curated_content` table.

## Tickets

**P6-CORE-01** (Partial): his outfits as lookbooks. Do not grow P6-SHOP catalog UI here.
