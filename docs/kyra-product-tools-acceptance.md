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

## Studio chat confirmation groundwork

`tools/studioConfirmation.ts` and two passing tests cover conservative direct
preview commands and affirmative replies bound to a server-owned selection key
and cost prompt. Questions, negation, cancellation and mismatched selections do
not authorize paid generation. This guard is not registered yet.

Current saved photos use private storage paths, whereas the master tool schema
uses reference UUIDs. Current Studio photo consent is attested by the native
request, not available as a durable Kyra authorization record. Before enabling
chat generation, implement durable consent/reference identity and persisted
selection-bound confirmations; enforce owned items/photos and deduplicate jobs
per approved turn. Never synthesize consent from a model tool argument or treat
this isolated guard as completion of the Studio preview feature.

The unregistered Studio preview executor now validates exclusive outfit/item
selection, bounded UUID items and display options. It requires exact selection
confirmation and current owned-photo consent before calling its job service.
Four executor tests plus two confirmation tests passed. Durable reference lookup,
confirmation storage, native consent registration, Studio enum mapping, high-res
support and per-turn job deduplication remain open; this is not deployed.

## Existing reference identity and consent source

Inspection of `reference_photo_key` in ADR 0026's deployed migration confirmed
that saved `.jpg` filenames already contain reference UUIDs. `studioReferences.ts`
resolves that UUID only under the verified user's folder, requires the path to
remain in `body_profiles.appearance.reference_selfie_paths`, and requires a live
owned Studio row with a current acknowledged server-accepted consent receipt.
Only `id` is selected from Studio rows, excluding job leases and prompt contents.
A photo never accepted by native Studio remains unavailable for chat generation;
no consent is synthesized for it. This supersedes the earlier assumption that a
new reference-identity schema is necessary.

`studioRequest.ts` maps chat pose/background choices to existing API enums and
passes the real Studio request parser. Current draft-only service cannot fulfill
hi-res requests; these fail explicitly. Reference resolution and request mapping
have six fixture tests. Full service wiring, hosted RLS/erasure races, persisted
confirmation and per-turn job deduplication remain open. No deployment yet.

## Durable submission deduplication

New, unapplied migration `20261009000859_studio_submission_idempotency.sql`
adds a server-only request ledger and service-only enqueue wrapper. The wrapper
shares the existing per-user transaction lock, binds a request UUID to a SHA-256
request fingerprint and one generation, returns that generation for a replay,
rejects changed fingerprints and rejects removed jobs. The original atomic
allowance RPC still creates the first job, inside the same transaction.

All scratch SQL/RLS suites passed including test 37: same job ID on replay, one
allowance, conflict rejection, tombstone rejection and authenticated RPC denial
(`/tmp/astra-submission-rls.log`). Scratch database was removed. This is sequential
SQL coverage; concurrent/live checks and HTTP fingerprint/header wiring remain
open. The migration is not deployed. CLI 2.101.0 was killed by macOS; migration
creation succeeded through CLI 2.75.0, without changing migration history.

## Studio API submission wiring

`Idempotency-Key` is now parsed as a UUID; normalized parsed request bodies receive
canonical SHA-256 fingerprints. The job store checks existing owner-bound
requests before the trial quota and uses the atomic wrapper for initial keyed
inserts. The quota branch rechecks after its allowance read to avoid returning a
false limit error when another matching request just committed. Conflicting keys
and removed jobs return 409. Existing explicit failed-job retry behavior remains.

61 Studio tests passed (`/tmp/astra-submission-api-tests.log`), including canonical
fingerprints and an initial-submit replay after the free allowance was spent.
Entrypoint type checking and lint passed. Native API calls already send a stable
UUID Idempotency-Key for generateStudio; the deployed backend currently ignores
it. Migration must be deployed before this backend version. Concurrent database
and hosted HTTP verification remain open; no deployment yet.

## Verified deployment — Studio submission deduplication

Migration version **20261009000859** is applied; local filename matches hosted
history. Studio **ACTIVE v16**, verify_jwt=true, is deployed. The earlier
unapplied/undeployed notes above describe intermediate checkpoints.

- Overlapping local transactions returned one job, one allowance and one ledger
  record; scratch database removed. Setup `/tmp/astra-submission-concurrency-setup2.log`.
- Live concurrent HTTP submissions returned the same job. Replay after trial usage
  returned 202; changed payload 409, malformed key 400, genuinely new trial request
  429. Another account using the same key received its own job.
- Both disposable account deletions returned 202; SQL confirmed zero remaining
  QA users, generations and submission records. No provider generation was polled.
- Live privileged RPC execute grants are false for anon/authenticated.
- Report `/tmp/astra-submission-live-report.json`. ADR 0030 records architecture.
- Security scan still has existing findings plus intentional no-policy INFO for
  this service-only ledger; it is not an all-clear scan.

Build 20's existing stable submission keys now use this backend protection; no
new native build is necessary for this deployment. Kyra preview service wiring
and persisted confirmations remain open.

## Kyra-to-Studio service adapter

`studioServices.ts` now translates a verified chat turn to the owned Studio API.
The persisted user-message UUID is its Idempotency-Key, so repeated tool attempts
reuse the deployed submission ledger; changing the selection in that same turn
returns a conflict. Requests forward the caller JWT and use only the configured
Studio URL. Returned jobs must belong to that user. Quota/conflict failures are
clear domain outcomes. Queue timing is an approximate 120-second estimate,
not a guaranteed completion time; completed/failed replay states are retained.

127 Kyra tests passed (`/tmp/astra-kyra-studio-service-tests.log`), including
request header ownership and wrong-owner/quota/conflict response tests. Lint and
entrypoint type checks passed. This adapter is not registered or deployed yet:
reference IDs must be exposed in owned context, selection-bound confirmation
must persist between turns, and native job presentation/polling needs acceptance.

## Selection-bound confirmation storage

Unapplied migration `20261009001316_kyra_studio_confirmations.sql` adds a
server-only, conversation-owned confirmation record with a 30-minute expiry.
Preparation reuses an unchanged active selection, closes a changed/expired one,
and validates the conversation owner. RLS and revoked client grants prevent
clients from reading or preparing these records. The service role has an explicit
conversation SELECT grant; the first fixture run identified and corrected its
absence before any deployment.

The complete scratch SQL/RLS suite passed, including unchanged selection reuse,
selection replacement, expiry replacement, peer-thread rejection and client
read/RPC denial (`/tmp/astra-kyra-confirmation-final-rls.log`). Scratch DB removed.
This schema is not deployed. Runtime wiring must persist the record only for an
actually stored/displayed cost question, bind it to that assistant prompt,
reject closed/expired pending choices, and use its confirmation ID as the stable
Studio key across affirmative retries. Those steps remain open.

## Saved assistant prompt binding

The still-unapplied confirmation migration now binds each pending selection to
a persisted assistant message through a composite message/thread/owner foreign
key. Its service-only preparation rejects absent, empty or non-assistant prompts.
Reasking about an unchanged selection preserves its request ID and updates the
bound prompt and expiry; deleting that prompt cascades its confirmation record.
The explicit service SELECT grant now includes messages. This storage binding
does not by itself establish that a message contained the correct cost disclosure:
the runtime must generate the disclosure, persist it, and then prepare the record.

The complete scratch SQL/RLS suite passed, including latest-prompt binding and
rejection of a user-message prompt (`/tmp/astra-kyra-prompt-binding-rls.log`).
The scratch database was dropped. Live deployment, runtime confirmation handling,
cancellation/expiry enforcement and native job presentation remain open.
