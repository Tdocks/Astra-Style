# ADR 0030: Durable idempotency for initial Studio submissions

Date: 2026-10-08
Status: Accepted

## Context

Native generation requests already carry a stable UUID Idempotency-Key, but
Studio only deduplicated provider execution and explicit failed-job retries.
Repeated initial requests could create separate jobs and consume extra usage.

## Decision

The API fingerprints its normalized request body with canonical SHA-256 and
checks a server-owned `(user_id, request_key)` record before the trial quota.
Initial inserts use a service-only RPC wrapper sharing the existing per-user
allowance transaction lock. The record, job and allowance commit together.
Replays return the original visible job. Changed payloads and deleted jobs return
409 instead of spending another allowance. A second lookup in the quota branch
handles another matching request committing between the lookup and quota read.

The request ledger has RLS, no client grants or policies, and only service-role
access. A composite owner/job foreign key prevents mixed-owner records. Account
and physical job deletion cascade records; soft-deleted jobs retain their request
identity so a stale replay cannot resurrect them. No request payload or image is
stored in the ledger, only its fingerprint and linked job identity.

## Evidence and limits

SQL/RLS and 61 backend tests passed. Overlapping local database transactions and
live simultaneous HTTP requests returned one job/allowance. Hosted owner-scoped
keys, conflicts, malformed keys and trial limits passed; QA accounts/jobs/request
records were erased. Migration version 20261009000859 and Studio v16 are deployed.
The security advisor's no-policy INFO for this service-only ledger is intentional;
other existing advisor findings remain separately tracked. This does not complete
Kyra preview confirmation persistence, subscription limits or device acceptance.
