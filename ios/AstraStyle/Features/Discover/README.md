# Discover

Owns the Discover tab (master spec §6.21).

## Current surface

Saved looks, opt-in public worn looks (ADR 0017), and evaluated wardrobe-gap Unlocks remain first. Style, seasonal, fit, and brand guides follow under ADR 0046, restoring educational content requested in the full master-plan implementation.

`BundleDiscoverEditorialRepository` loads the versioned `Resources/Discover/discover-guides.json` configuration. It validates published content, ordering, duplicate identifiers, sources, and disclosures. Guide detail routes render complete articles. Brand field notes are independent unpaid editorial with primary-source links; sponsored entries require visible card and detail disclosures.

Unlocks continue to use `ShoppingRepository.fetchUnlocks`, not a generic shopping feed. Public looks preserve owner opt-in and worn-only visibility. The bundled configuration is editable in the repository and ships with app releases; it is not a hosted CMS.

## Ticket

P6-CORE-01: verify the configuration, all four article categories, detail routing, and commercial disclosure alongside existing privacy acceptance before marking complete.
