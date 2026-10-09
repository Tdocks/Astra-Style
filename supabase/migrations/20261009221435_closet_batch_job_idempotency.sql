-- Persist batch enqueue identity so a client retry after a lost 202 response
-- returns the original job instead of creating duplicate analysis work.
-- Owner scoping stays on the existing job row and its RLS policies.
alter table public.closet_analysis_jobs
  add column idempotency_key text,
  add column request_hash text,
  add column processing_token uuid,
  add column processing_until timestamptz;

alter table public.closet_analysis_jobs
  add constraint closet_analysis_jobs_idempotency_key_length
    check (idempotency_key is null or length(idempotency_key) between 1 and 128),
  add constraint closet_analysis_jobs_request_hash_sha256
    check (request_hash is null or request_hash ~ '^[0-9a-f]{64}$'),
  add constraint closet_analysis_jobs_idempotency_pair
    check ((idempotency_key is null) = (request_hash is null)),
  add constraint closet_analysis_jobs_processing_lease_pair
    check ((processing_token is null) = (processing_until is null));

create unique index closet_analysis_jobs_owner_idempotency_key_idx
  on public.closet_analysis_jobs (user_id, idempotency_key);

-- Batch jobs and their claim tokens are written only by the authenticated
-- Edge Function. Direct client mutation could forge jobs, erase the
-- idempotency record, or steal/release another poll's claim. Owner SELECT
-- remains available under the existing RLS policy; account deletion still
-- cascades through the auth.users foreign key.
revoke all on public.closet_analysis_jobs from anon, authenticated;
grant select on public.closet_analysis_jobs to authenticated;
grant select, insert, update on public.closet_analysis_jobs to service_role;

comment on column public.closet_analysis_jobs.idempotency_key is
  'Client-supplied stable key for retry-safe batch enqueue, unique per owner; null for jobs created before this contract.';
comment on column public.closet_analysis_jobs.request_hash is
  'SHA-256 of the canonical batch body; reusing an owner key with another body is a conflict.';
comment on column public.closet_analysis_jobs.processing_token is
  'Opaque owner-worker claim token; only its current holder may persist a poll result.';
comment on column public.closet_analysis_jobs.processing_until is
  'Expiry for the current status-poll claim, allowing recovery if an edge request exits unexpectedly.';
