# ADR 0038 — Premium Studio high-resolution export

Date: 2026-10-09
Status: Accepted; backend implemented locally, native integration and deployment pending

## Context

Studio's normal render is the medium-quality draft. The provider already supports a high-quality portrait render, but there is no separate export action. The Premium reservation budget is 20 new renders per UTC month by default; one reservation is charged for each new render, and failed work may release its reservation. There is no separate high-resolution allowance.

## Decision

Add an explicit authenticated `POST /studio/export-hi-res` action. It accepts only an owned draft generation UUID and, for reference-photo jobs, a fresh acknowledgment of the current photo-consent terms. A service-only transaction locks the source and user, requires an active Premium subscription, and accepts only a completed, nondeleted, non-hi-res source whose private result path is canonical and whose retention has not expired. It creates at most one high-resolution child per source. The child copies the source prompt, garments, controls, and original reference path exactly, records a separate fresh consent receipt where applicable, and changes only the provider resolution to `hi_res`.

The child is a new Studio generation and reserves one existing monthly Studio allowance. It has its own generation UUID, private result object, normal retention window, status polling, deletion, and account-deletion behavior. A failed child uses the existing retry endpoint and reuses its reservation. Repeated export submissions resolve to the latest retry in that same export lineage. The explicit POST only queues work; the existing status GET remains the mechanism that advances jobs and may submit the provider render. No GET export endpoint or GET-triggered export creation is added.

Generation ownership, subscription state, source eligibility, idempotency, and allowance reservation are enforced in the transaction. Source deletion and expiration wait while a live hi-res child depends on it. The expiry sweep processes the child first; after its Storage cleanup succeeds and the child row is removed, a later sweep can expire the source, so dependency protection does not pin sources permanently. Retrying an already-created child remains available under existing semantics; each retry carries the same source dependency and reuses its allowance. A new export cannot be created from an expired source.

## Consequences

- No new quota or billing configuration is introduced. The existing Premium monthly reservation is authoritative; the free lifetime trial cannot export hi-res.
- Photo-based re-rendering requires renewed consent at the current terms version. Flat-lay inspiration needs no identity-photo consent.
- Native UI must disclose that the action uses one remaining Premium Studio render before the user confirms it. The client feature must stay hidden until the entitlement/allowance copy and complete flow are verified.
- Export quality and image fidelity still require live-provider and device acceptance. This ADR does not authorize deployment.
