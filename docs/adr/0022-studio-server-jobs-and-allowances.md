# ADR 0022 — Server-owned Studio jobs and durable allowances

Date: 2026-10-08. Status: accepted, implemented and deployed (Studio v9, Profile v11).

## Context

The existing caller-scoped job store allowed authenticated direct inserts and updates. That bypassed endpoint consent, prompt validation and quota checks. Counting visible jobs separately from insertion also permitted concurrency races and refunded a free trial when a completed preview was deleted. Multiple status polls could submit the same queued job concurrently.

## Decision

Use the platform-injected service credential only for Studio job bookkeeping. Authentication, garment access and image storage continue through the caller's JWT and RLS. Every privileged job operation fences the verified user ID; status updates additionally fence a job claim token. No service credentials enter the app.

An invoker RPC available only to service_role serializes enqueueing per user with a transaction advisory lock. A durable allowance is reserved with the job, consumed only on success, and retained after preview deletion. Non-retryable failures release reservations. Provider-side retryable failures reuse the reservation; repeat retry requests return the same child job. Deleting the latest failed attempt abandons its reservation, while deleting historical ancestors cannot refund a running or successful retry.

A second service-only invoker RPC atomically claims queued/generating jobs with a 180-second lease. The provider deadline is 90 seconds. The token fences writes and release; a stale worker cannot overwrite a replacement claim. Network/provider ambiguity still requires the adapter's stable idempotency key and deterministic result path; this does not claim exactly-once delivery across a provider outage.

Authenticated callers retain owned reads and deletion of terminal previews. Insert/update grants and policies are removed. Allowance activity permits owned reads for data export, with no client writes. Export excludes operational claim tokens/leases.

## Deployment order

1. Apply the expansion migration (tables, nullable lineage columns, backfill, RPCs and triggers). Legacy endpoints continue working.
2. Deploy the new Studio and Profile functions. New writes use the RPC and profile export includes owned allowance activity.
3. Apply the lockdown migration, backfilling any jobs created during rollout, enforcing the allowance reference, and removing client job writes.
4. Verify authenticated direct writes/RPC calls are rejected, concurrent enqueue/claim behavior, retry lineage, deletion accounting, exports and cleanup.

All existing app endpoint shapes remain compatible. The Edge DTO omits new operational metadata; direct owned row reads tolerate extra columns.

## Evidence

Local regression: 61 Studio/provider/export tests passed; 155 RLS assertions passed, followed by reservation/lease/retry/deletion SQL checks on a clean scratch database. Live disposable-account acceptance admitted one of two concurrent free enqueue requests (202/429), rejected direct insert/update/claim RPC calls (403), hid the job from a second account (404), returned generating/queued for concurrent status polls, and completed one live render. Owned export returned 25 tables with consumed usage and no claim tokens. After image and preview deletion, a new free request still returned 429. Both disposable accounts were confirmed deleted and their deletion audit records completed. Security advisor findings were the existing owner-scoped anonymous-access warnings and the intentionally service-only pending notification table.

## Limits and follow-up

Historical hard-deleted jobs cannot be reconstructed; backfill preserves available history conservatively. Old retries have no reliable lineage and are separate legacy reservations. Premium's configurable monthly quantity remains a subscription economics decision; do not describe this free-trial/concurrency repair as a complete Premium spend cap. High-resolution export and caching identical combinations while preserving intentional rerolls remain separate work.
