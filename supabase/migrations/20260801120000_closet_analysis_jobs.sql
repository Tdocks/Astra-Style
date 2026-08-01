-- ============================================================================
-- Astra Style — Closet analysis jobs + idempotency
-- ============================================================================
-- Supports P3-SCAN-07 / P3-SCAN-08:
--   * `closet_analysis_jobs` — durable queue for `POST /closet/batch-analyze`
--     so batch work is job+poll rather than an in-request fan-out that would
--     saturate the shared `closet` isolate (HANDOFF §9.3 / ADR 0013).
--   * `closet_analysis_idempotency` — stores the response for a caller-
--     supplied Idempotency-Key on `POST /closet/analyze-item`, so a mobile
--     retry of a paid vision call cannot double-charge (docs/08 §0.1,
--     HANDOFF §9.2).
--
-- Append-only migration: do not edit once applied.
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- closet_analysis_jobs
-- ----------------------------------------------------------------------------
create table if not exists public.closet_analysis_jobs (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  -- Reuses generation_status (queued/generating/complete/failed) — the same
  -- state machine studio_generations uses, and the same vocabulary the iOS
  -- poll client already understands from Style Studio.
  status          generation_status not null default 'queued',
  -- Submitted analyze elements: [{request_id, storage_path, image_type, device_hints}, ...]
  items           jsonb not null default '[]'::jsonb,
  -- Per-item outcomes keyed for the wire batch shape:
  -- [{request_id, result}|{request_id, error}, ...]
  results         jsonb not null default '[]'::jsonb,
  error_message   text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint closet_analysis_jobs_items_is_array check (jsonb_typeof(items) = 'array'),
  constraint closet_analysis_jobs_results_is_array check (jsonb_typeof(results) = 'array')
);

comment on table public.closet_analysis_jobs is
  'Batch garment-analysis job queue for POST /closet/batch-analyze (P3-SCAN-08). Enqueue returns a job id; GET /closet/batch-status/:id advances and returns progress. Never processed as a synchronous fan-out on the interactive analyze-item path.';
comment on column public.closet_analysis_jobs.items is
  'Submitted per-image elements (request_id + private storage_path + optional device_hints). Image bytes never live here.';
comment on column public.closet_analysis_jobs.results is
  'Per-item outcomes in ClosetItemAnalysisBatch wire shape. A failure on one item must not fail the batch.';

create index if not exists closet_analysis_jobs_user_created_idx
  on public.closet_analysis_jobs (user_id, created_at desc);

create index if not exists closet_analysis_jobs_status_idx
  on public.closet_analysis_jobs (status)
  where status in ('queued', 'generating');

drop trigger if exists trg_set_updated_at on public.closet_analysis_jobs;
create trigger trg_set_updated_at
  before update on public.closet_analysis_jobs
  for each row execute function public.set_updated_at();

alter table public.closet_analysis_jobs enable row level security;

create policy closet_analysis_jobs_select_own on public.closet_analysis_jobs
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy closet_analysis_jobs_insert_own on public.closet_analysis_jobs
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy closet_analysis_jobs_update_own on public.closet_analysis_jobs
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy closet_analysis_jobs_delete_own on public.closet_analysis_jobs
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- ----------------------------------------------------------------------------
-- closet_analysis_idempotency
-- ----------------------------------------------------------------------------
create table if not exists public.closet_analysis_idempotency (
  user_id           uuid not null references auth.users(id) on delete cascade,
  idempotency_key   text not null,
  -- SHA-256 hex of the canonical request body, so the same key with a
  -- different body is a conflict rather than a silent wrong replay.
  request_hash      text not null,
  response_payload  jsonb not null,
  created_at        timestamptz not null default now(),
  primary key (user_id, idempotency_key),
  constraint closet_analysis_idempotency_key_nonempty check (char_length(idempotency_key) between 1 and 128),
  constraint closet_analysis_idempotency_hash_nonempty check (char_length(request_hash) = 64)
);

comment on table public.closet_analysis_idempotency is
  'Idempotency store for POST /closet/analyze-item. Keyed on (user_id, Idempotency-Key); replays the stored ClosetItemAnalysisResult when the request hash matches.';

create index if not exists closet_analysis_idempotency_created_idx
  on public.closet_analysis_idempotency (created_at);

alter table public.closet_analysis_idempotency enable row level security;

create policy closet_analysis_idempotency_select_own on public.closet_analysis_idempotency
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy closet_analysis_idempotency_insert_own on public.closet_analysis_idempotency
  for insert to authenticated
  with check (user_id = (select auth.uid()));

-- Updates/deletes are not granted to authenticated clients — rows are
-- append-only from the caller's perspective. An Edge Function holding the
-- caller's JWT can insert and select; cleanup of stale keys is a future
-- scheduled job (same shape as ADR 0010's abandoned-upload sweep).
