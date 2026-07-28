-- ============================================================================
-- Astra Style — 10. Row Level Security
-- ============================================================================
-- §15: "Every user-owned table must enforce user_id = auth.uid()." We use the
-- subquery form `user_id = (select auth.uid())` throughout, not the bare
-- `user_id = auth.uid()` call, per the project convention: wrapping the
-- function call in a subquery lets Postgres evaluate it once per statement
-- (as an InitPlan) instead of once per row, which the Postgres/Supabase
-- planner takes advantage of on sequential/index scans over many rows.
--
-- Tables and their RLS shape:
--   - profiles: predicate on `id` (id IS the user id — see profiles table
--     comment). No insert/delete policy for `authenticated`: rows are created
--     only by handle_new_user() (SECURITY DEFINER trigger) and deleted only by
--     the auth.users cascade during account deletion, never directly by client
--     code. Only select + update policies are granted to authenticated users.
--   - Ordinary user-owned tables (style_profiles, body_profiles, ...,
--     studio_generations): full select/insert/update/delete, predicate on
--     user_id.
--   - Denormalized-user_id child tables (closet_item_images, outfit_items,
--     kyra_messages): predicate on their own user_id column directly (fast,
--     no join). The set_child_user_id() trigger family
--     (20260728101200_functions_and_triggers.sql) both populates that column
--     from the parent AND, as a side effect, rejects an insert against a
--     parent row owned by a different user (see that migration's comments).
--   - product_candidates: shared catalog, not user-owned. Read-only to
--     authenticated users; writes are service-role only (no policy granted to
--     `authenticated`, so RLS default-denies inserts/updates/deletes for that
--     role; service_role bypasses RLS entirely per Supabase platform default).
--   - subscriptions: read-only to the owning user. Written only by Edge
--     Functions using the service-role key (POST /subscriptions/sync, the App
--     Store webhook) — never directly by client code, so no insert/update/
--     delete policy is granted to `authenticated`.
--   - account_deletions: policies defined in
--     20260728101300_account_deletion.sql, alongside the table itself.
--
-- We enable (not FORCE) row level security: FORCE ROW LEVEL SECURITY would
-- also constrain the table owner role that runs migrations/admin maintenance
-- queries, which is not what we want for an operational Postgres role. RLS as
-- enabled here already fully constrains the `authenticated` and `anon` API
-- roles that Supabase's PostgREST/Edge Function-with-user-JWT paths use.
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- profiles (predicate on id, not user_id)
-- ----------------------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- No insert/delete policy for `authenticated`: profiles are created only by
-- handle_new_user() and removed only via the auth.users cascade.

-- ----------------------------------------------------------------------------
-- Standard user_id-owned tables: enable RLS + select/insert/update/delete,
-- generated via a loop to avoid ~80 near-identical statements.
-- ----------------------------------------------------------------------------
do $$
declare
  t text;
  owned_tables text[] := array[
    'style_profiles', 'body_profiles', 'lifestyle_profiles',
    'closet_items', 'closet_item_images',
    'outfits', 'outfit_items', 'outfit_wears',
    'style_feedback', 'style_memories',
    'kyra_threads', 'kyra_messages',
    'occasions', 'daily_briefs',
    'studio_generations',
    'user_product_evaluations'
  ];
begin
  foreach t in array owned_tables loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists %I on public.%I', t || '_select_own', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (user_id = (select auth.uid()))',
      t || '_select_own', t
    );

    execute format('drop policy if exists %I on public.%I', t || '_insert_own', t);
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (user_id = (select auth.uid()))',
      t || '_insert_own', t
    );

    execute format('drop policy if exists %I on public.%I', t || '_update_own', t);
    execute format(
      'create policy %I on public.%I for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))',
      t || '_update_own', t
    );

    execute format('drop policy if exists %I on public.%I', t || '_delete_own', t);
    execute format(
      'create policy %I on public.%I for delete to authenticated using (user_id = (select auth.uid()))',
      t || '_delete_own', t
    );
  end loop;
end
$$;

-- ----------------------------------------------------------------------------
-- product_candidates: shared catalog, read-only to authenticated users.
-- ----------------------------------------------------------------------------
alter table public.product_candidates enable row level security;

drop policy if exists product_candidates_select_all on public.product_candidates;
create policy product_candidates_select_all on public.product_candidates
  for select to authenticated
  using (true);

-- No insert/update/delete policy for `authenticated`: catalog rows are
-- written only by service-role Edge Functions (POST /products/extract, the
-- admin ingestion job, and affiliate feed sync).

-- ----------------------------------------------------------------------------
-- subscriptions: read-only to the owning user.
-- ----------------------------------------------------------------------------
alter table public.subscriptions enable row level security;

drop policy if exists subscriptions_select_own on public.subscriptions;
create policy subscriptions_select_own on public.subscriptions
  for select to authenticated
  using (user_id = (select auth.uid()));

-- No insert/update/delete policy for `authenticated`: writes come only from
-- POST /subscriptions/sync and the App Store webhook, both service-role.
