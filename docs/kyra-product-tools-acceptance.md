# Kyra product tools implementation

8 October 2026. Work in progress; not deployed.

## Implemented locally

- `analyze_product` validates one URL or candidate UUID and rejects unsafe URLs.
- Production wiring forwards the caller JWT to the existing product extraction
  and evaluation routes. Those routes retain SSRF guards, quota checks, catalog
  normalization and wardrobe evaluation. Kyra uses no service-role key.
- Catalog candidate lookup uses a caller-scoped client; only mapped public product
  attributes reach the model.
- Tool output preserves measured compatibility, converts redundancy from 0–100
  to 0–1, retains unknown price/cost fields, and labels affiliate links.
- Allowance/authentication/invalid-product failures are domain results rather than
  infrastructure retries. Server failures retain the existing Kyra retry policy.

## Evidence

109 Kyra tests passed (`/tmp/astra-kyra-product-tests2.log`), including the new
service adapter, tool and conversation registration checks. Deno entrypoint type
checking and new module linting passed. These are offline fixture tests.

## Still required before deployment/completion

- Product service now returns the existing engine’s `fills_gap` and before/after
  bucket details; Kyra preserves them. This engine currently measures the caller’s
  single occasion (default `unconstrained`), not a full occasion sweep. Broader
  occasion coverage and hosted deployment remain open.
- Confirm safe behavior for extraction uncertainty and available card fields.
- Hosted ownership, allowance and real provider acceptance, with disposable QA
  identities and catalog cleanup.
- `search_products` and confirmed `generate_studio_preview` remain stubs.
- Audit mutation retries/duplicate evaluations and quota concurrency alongside
  the shared product service.

Product/Kyra combined regression: 163 tests passed
(`/tmp/astra-product-gaps-tests.log`); gap-result propagation fixture also passed.

## Catalog search groundwork

`tools/searchProducts.ts` now validates query/filter bounds, sorts supplied
organic relevance without consulting sponsorship, deduplicates candidates,
labels affiliate links and returns an explicit empty result. Four fixture tests
and lint passed. Strict filters reject unknown prices/colors/formality and inferred
category defaults. This module is not registered in production yet: the catalog
query, semantic relevance provider/index, filter enforcement and hosted checks
remain to be implemented. It is not a completed search feature.

Embedding-provider credential reuse confirmation is pending under the OpenAI
API-key skill. Continue non-provider work while awaiting that answer. Budget
filter currency context also needs explicit handling before hosted search acceptance.
