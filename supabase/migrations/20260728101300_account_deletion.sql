-- ============================================================================
-- Astra Style — 14. Account deletion
-- ============================================================================
-- §15 "Data deletion" requires account deletion to remove: database rows,
-- storage objects, generated images, embeddings, style memories, and the auth
-- identity — and explicitly allows an async job with user-visible status if
-- immediate deletion cannot complete synchronously. §14 exposes this as
-- `DELETE /account`.
--
-- Why this cannot be one SQL transaction:
--   - Deleting the auth.users row is a GoTrue Admin API operation
--     (`supabase.auth.admin.deleteUser(user_id)`), not a SQL statement a
--     regular migration/RPC can issue directly.
--   - Deleting the *actual* objects backing storage.objects rows (the blobs
--     in the storage backend, not just their Postgres metadata rows) is a
--     Storage API operation from an Edge Function holding the service-role
--     key, not a guaranteed side effect of `delete from storage.objects`
--     alone across all Supabase storage-api versions.
-- So this migration provides the SQL half (the audit/status table + the two
-- privileged helper functions) and documents the exact Edge Function
-- orchestration the DELETE /account handler must perform around them.
--
-- Required orchestration, in `supabase/functions/account` (Edge Function,
-- service-role key, per §25) — NOT `account-delete`: Supabase routes
-- `/functions/v1/{slug}/...` by the first path segment only, the client
-- builds `DELETE {base}/account` (`AstraEndpoint.deleteAccount`), and
-- `EndpointDeploymentMappingTests.expectedSlugs` on the iOS side requires
-- the slug `account`. A function deployed as `account-delete` would 404 on
-- every real call while every unit test on both sides stayed green — see
-- docs/adr/0013-edge-function-routing.md, which documents this exact
-- failure mode happening once already with `outfits-generate`:
--   1. Validate the caller's JWT; get user_id.
--   2. `select public.request_account_deletion();` (run with the user's own
--      JWT/claims, or by the edge function passing through auth.uid() context)
--      -> returns deletion_id. Respond to the client immediately with
--      202 Accepted + deletion_id so the UI can show "deletion in progress"
--      (§15's async-job allowance) rather than blocking on the steps below.
--   3. Using the service-role client, list and remove every object under
--      `users/{user_id}/` in the `user-content` bucket via the Storage API
--      (`storage.from('user-content').remove([...])`), covering the closet/,
--      references/, and studio/ subpaths (§15 path convention) — this is the
--      actual blob deletion, not just metadata.
--   4. `select public.finalize_account_deletion(deletion_id);` (service role)
--      — defense-in-depth metadata cleanup + records the one-way audit hash
--      while user_id is still known, and flips status to 'processing'.
--   5. `supabase.auth.admin.deleteUser(user_id)` (GoTrue Admin API, service
--      role). This deletes the auth.users row, which cascades via
--      `on delete cascade` through every user_id foreign key in this schema —
--      profiles, style_profiles, body_profiles, lifestyle_profiles,
--      closet_items (+ closet_item_images), outfits (+ outfit_items,
--      outfit_wears), style_feedback, style_memories (+ their embeddings,
--      since the embedding column lives on the row being deleted),
--      kyra_threads (+ kyra_messages), occasions, daily_briefs,
--      studio_generations, subscriptions, and user_product_evaluations. This
--      single Admin API call is therefore what actually satisfies "Database
--      rows ... Embeddings ... Style memories" from §15 for every table
--      except the shared product_candidates catalog, which is correctly NOT
--      user data and NOT deleted.
--   6. `select public.mark_account_deletion_complete(deletion_id);`
--      (service role) — sets status = 'completed'.
--   On any failure in steps 3-5: `select public.mark_account_deletion_failed(deletion_id, reason);`
--   so the client-visible status reflects it and support/retry tooling can
--   pick it up, instead of leaving the row silently stuck at 'processing'.
--
-- Real-world caveat (flagged, not resolved, per project scope): subscriptions
-- rows are deleted by the auth.users cascade along with everything else,
-- matching §15's literal "database rows" requirement. A production system
-- would revisit this with legal/finance before launch — tax, chargeback, and
-- fraud-audit obligations often require retaining *anonymized* billing
-- records for a statutory period even after account deletion, which would
-- mean copying a minimal anonymized record out of `subscriptions` in
-- finalize_account_deletion() before the cascade runs, rather than deleting
-- it outright. No such anonymized-retention table is created here because the
-- spec gives no retention requirement to implement against.
-- ============================================================================

set search_path = public, extensions;

do $$ begin
  create type account_deletion_status as enum ('pending', 'processing', 'completed', 'failed');
exception when duplicate_object then null; end $$;

-- ----------------------------------------------------------------------------
-- account_deletions — status/audit table for the deletion job.
-- ----------------------------------------------------------------------------
-- user_id is intentionally `on delete set null` (not cascade): this row must
-- outlive the auth.users row it started against, both so the completed
-- job's audit trail survives and so mark_account_deletion_complete() can
-- still find/update it by primary key after step 5 above. user_id_hash is
-- the permanent, privacy-preserving record of *that a deletion happened*,
-- computed with pgcrypto's digest() before user_id is nulled — the raw id is
-- not retained once the job completes.
create table if not exists public.account_deletions (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid references auth.users(id) on delete set null,
  user_id_hash     text,
  status           account_deletion_status not null default 'pending',
  requested_at     timestamptz not null default now(),
  completed_at     timestamptz,
  failure_reason   text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table public.account_deletions is
  'One row per DELETE /account request; the user-visible "deletion in progress" status object required by §15. Not user-owned in the RLS sense once completed (user_id is nulled), so it is exempt from the standard owned_tables RLS loop in 20260728100900_rls_policies.sql and gets bespoke policies below.';
comment on column public.account_deletions.user_id_hash is
  'sha256(user_id) via pgcrypto digest(), retained after user_id is nulled so an operator can confirm "did user X''s deletion complete" without retaining the raw identifier indefinitely.';

drop trigger if exists trg_set_updated_at on public.account_deletions;
create trigger trg_set_updated_at
  before update on public.account_deletions
  for each row execute function public.set_updated_at();

alter table public.account_deletions enable row level security;

-- The owning user can poll status while their account still exists
-- (pending/processing). No insert/update/delete policy is granted to
-- `authenticated`: rows are only ever written by the SECURITY DEFINER
-- functions below.
drop policy if exists account_deletions_select_own on public.account_deletions;
create policy account_deletions_select_own on public.account_deletions
  for select to authenticated
  using (user_id = (select auth.uid()));

create index if not exists idx_account_deletions_user_id
  on public.account_deletions (user_id)
  where user_id is not null;

-- ----------------------------------------------------------------------------
-- request_account_deletion — step 2. Callable by the authenticated user.
-- ----------------------------------------------------------------------------
create or replace function public.request_account_deletion()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id  uuid;
begin
  if v_uid is null then
    raise exception 'request_account_deletion() requires an authenticated caller';
  end if;

  if exists (
    select 1 from public.account_deletions
    where user_id = v_uid and status in ('pending', 'processing')
  ) then
    raise exception 'An account deletion is already in progress for this user';
  end if;

  insert into public.account_deletions (user_id, status)
  values (v_uid, 'pending')
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.request_account_deletion() is
  'Uses auth.uid() only — never a client-supplied user id — so a caller can only request deletion of their own account. Returns the deletion_id the client polls via account_deletions.';

revoke all on function public.request_account_deletion() from public, anon, authenticated;
grant execute on function public.request_account_deletion() to authenticated;

-- ----------------------------------------------------------------------------
-- finalize_account_deletion — step 4. Service-role only.
-- ----------------------------------------------------------------------------
create or replace function public.finalize_account_deletion(p_deletion_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  select user_id into v_user_id
  from public.account_deletions
  where id = p_deletion_id;

  if v_user_id is null then
    raise exception 'account_deletions row % not found or already finalized', p_deletion_id;
  end if;

  -- Defense-in-depth storage metadata cleanup. The Storage API call in step 3
  -- of the orchestration above is the authoritative blob deletion; this
  -- statement additionally removes any storage.objects metadata rows the
  -- Storage API call may have missed (e.g. a partial failure on a prior
  -- attempt), scoped to this bucket's users/{user_id}/ prefix.
  if to_regclass('storage.objects') is not null then
    execute format(
      $sql$
        delete from storage.objects
        where bucket_id = %L
          and (storage.foldername(name))[1] = %L
          and (storage.foldername(name))[2] = %L
      $sql$,
      'user-content', 'users', v_user_id::text
    );
  end if;

  update public.account_deletions
  set status = 'processing',
      user_id_hash = encode(extensions.digest(v_user_id::text, 'sha256'), 'hex')
  where id = p_deletion_id;
end;
$$;

comment on function public.finalize_account_deletion(uuid) is
  'Service-role only. Must run AFTER the Edge Function''s Storage API blob deletion (step 3) and BEFORE auth.admin.deleteUser() (step 5) — see this file''s top-of-file orchestration comment.';

revoke all on function public.finalize_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.finalize_account_deletion(uuid) to service_role;

-- ----------------------------------------------------------------------------
-- mark_account_deletion_complete / _failed — steps 6 / error path.
-- ----------------------------------------------------------------------------
create or replace function public.mark_account_deletion_complete(p_deletion_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.account_deletions
  set status = 'completed',
      completed_at = now()
  where id = p_deletion_id;
$$;

revoke all on function public.mark_account_deletion_complete(uuid) from public, anon, authenticated;
grant execute on function public.mark_account_deletion_complete(uuid) to service_role;

create or replace function public.mark_account_deletion_failed(p_deletion_id uuid, p_reason text)
returns void
language sql
security definer
set search_path = public
as $$
  update public.account_deletions
  set status = 'failed',
      failure_reason = p_reason
  where id = p_deletion_id;
$$;

revoke all on function public.mark_account_deletion_failed(uuid, text) from public, anon, authenticated;
grant execute on function public.mark_account_deletion_failed(uuid, text) to service_role;
