# Profile

Owns the Profile tab: identity, stats, Style Journey, and privacy controls (spec §6.22, §6.23).

## What this module owns

- Profile header, Style DNA summary, Wardrobe Score, items owned, outfits created, cost per wear, most-worn colors, monthly spend.
- Style Journey timeline and the Monthly Review (§6.23): new items, spend, wears, best purchase, underused items, versatility change, next priority, and a challenge for next month.
- Subscription status display (management itself is **Subscription**'s screen; Profile links to it).
- Preferences (re-entry point into the Style DNA editing flow owned by **Onboarding**).
- Privacy and data controls: export personal data, view/delete style memories, delete individual reference/generated images, in-app account deletion (spec §29, §30).

## Governing spec sections

§6.22-§6.23 (screen specs), §9 (`profiles`), §10 (Wardrobe Score display), §15 (account deletion must remove DB rows, storage objects, generated images, embeddings, style memories, and the auth identity), §29 (privacy/legal requirements), §30 (Definition of Done items 13-14: view/delete style memories, delete the account).

## What already exists to build against

- `Domain/Repositories/ProfileRepository.swift` — `exportPersonalData()`.
- `Domain/Repositories/AuthRepository.swift` — `deleteAccount()`.
- `Domain/Repositories/KyraRepository.swift` — `fetchMemories()` / `deleteMemory(id:)` for the memory inspector, even though it's reached from Profile.
- `Domain/Repositories/ClosetRepository.swift` — `fetchWardrobeScore()`.

## Tickets

Spec's given ID prefixes don't include a dedicated Profile one. Given the heavy overlap with subscription status, privacy controls, and Style DNA, the most likely home is **P7-SUB** (account/subscription/privacy surface) with Style DNA display pulling from **P2-ONBOARD**'s output — confirm against `docs/02-task-breakdown.md` once it's finalized.
