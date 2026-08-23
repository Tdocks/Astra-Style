# `products` — P6-SHOP-03 / P6-SHOP-04 / Discover Unlocks

Three routes, one deployed function (ADR 0013 grouped-slug routing):

| Route | Ticket | What it does |
|---|---|---|
| `POST /products/extract` | P6-SHOP-03 | A pasted retailer URL becomes a `product_candidates` row. |
| `POST /products/evaluate` | P6-SHOP-04 | That row becomes a Kyra verdict against the caller's closet. |
| `POST /products/unlocks` | P6-CORE-01 | Products **this user already evaluated**, re-scored against **this closet**, `outfits_unlocked > 0`, ranked by that count. Not a `last_checked_at` catalog dump. |

## The P6-SHOP-09 guarantee, and where it actually lives

Spec §11: *affiliate availability must not change Kyra's verdict.*

That is enforced by a type boundary rather than by discipline.
`evaluation.ts` — the whole compute core — has no way to receive
sponsorship: `EvaluationInputs` declares no such field, so passing one is a
compile error rather than a review comment somebody has to catch. Search that
file for "sponsor" and there is nothing to find.

`handler.ts` **can** see `sponsored`, because the response has to carry the
label. The rule there is positional: it is read only after
`evaluateProductCandidate` has returned, and only to attach `sponsored:` to
the DTO. `ranking.ts` sorts alternatives on `organicScore` alone, and Unlocks on
`unlockCount` alone. Both break ties by input order — deliberately not
toward sponsored items (the failure §11 names) and deliberately not away
from them either (its mirror image, a penalty for being sponsored, which
is not what "separate" means).

## Env

| Variable | Default | Meaning |
|---|---|---|
| `PRODUCT_EXTRACTION_PROVIDER` | mock | `html` selects the live extractor. Anything else, including unset, uses deterministic fixtures. |

Defaulting to the mock is the same policy `closet/` uses for vision: a deploy
that forgets to configure a provider produces fixtures rather than silently
making server-side requests to retailers on a user's behalf.

## What the live extractor genuinely does, versus what §17 would prefer

`HtmlProductExtractionProvider` fetches the page and reads structured
metadata — Open Graph, JSON-LD, microdata — falling back to heuristics over
the URL path. §17 lists three ingestion options and warns against relying on
unrestricted scraping as the *only* product source. This is option 3
(user-pasted URLs analysed on demand), which is what P6-SHOP-03 scopes.
Options 1 and 2 — a curated admin catalog and retailer affiliate feeds — are
P6-SHOP-08 and are not built.

Extraction is honest about its own gaps: `unreadFields` records what the
provider could not read off the page, and a hostname is *not* a retailer
name. `candidateMapper.ts` separately derives a display fallback from the
domain, so a row still has a retailer — but the provider does not claim to
have read one, because `unreadFields` is the only signal the decision page
has for "we are guessing at this".

## Deliberately not built

- **Caching of evaluations.** Each call re-scores. A man's closet changes
  between evaluations and a cached verdict would age badly in the one
  direction that matters — becoming more confident as it becomes more wrong.
- **Wishlist / purchased actions** (P6-SHOP-07) and the `wishlist_items`
  migration behind them. Deferred on purpose until the UI that has to live
  with the schema exists.
- **Curated catalog ingestion** (P6-SHOP-08).
- **Fragrance.** It has no wardrobe-graph role, so there is no pairing
  question to answer; `/evaluate` returns a 400 saying so rather than
  inventing a verdict.
