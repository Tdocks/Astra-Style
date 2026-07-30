-- ============================================================================
-- supabase/tests/20_rls_isolation_tests.sql
-- ============================================================================
-- Automated RLS isolation suite — one section per user-owned table, per the
-- Phase 1 roadmap's top risk (docs/01-build-roadmap.md, Phase 1 "Risks"):
--
--   "RLS policies that 'work' in manual testing but have a gap (e.g.,
--   missing policy on an INSERT) — this is a security bug that won't
--   surface until Phase 3+ when real user data exists. Mitigate with an
--   automated RLS test per table, not manual QA."
--
-- FORMAT CHOICE: plain SQL, not pgTAP
-- ------------------------------------
-- pgTAP was confirmed installable in the environment this suite was written
-- in (`apt-get install postgresql-16-pgtap`), but it was NOT chosen, for
-- portability: the standard `postgres:16` / `pgvector/pgvector:pg16` Docker
-- images used as GitHub Actions service containers (see
-- .github/workflows/rls-tests.yml) do not ship pgTAP, and there is no
-- supported way to `CREATE EXTENSION pgtap` inside a service container's
-- startup (service containers take image/env/health-check options only, not
-- setup steps). Requiring a custom pgTAP-flavored Postgres image would add
-- an external image-maintenance dependency for a test suite that doesn't
-- need pgTAP's assertion library to do its job. Plain SQL with explicit
-- `raise exception` on failure needs nothing beyond the `postgres:16`/
-- `pgvector/pgvector:pg16` image already required for pgvector, runs
-- anywhere `psql` does, and is exactly as capable of catching a real RLS
-- gap as `is()`/`ok()` would be.
--
-- WHAT THIS PROVES PER TABLE
-- --------------------------
-- For every ordinary user-owned table (predicate `user_id = auth.uid()`, or
-- `id = auth.uid()` for `profiles`):
--   1. User A can SELECT their own row.
--   2. User A gets ZERO ROWS (not an error) selecting user B's row.
--   3. User A CANNOT INSERT a row for another user — this is the specific
--      gap the roadmap calls out: a missing `WITH CHECK` on INSERT is
--      invisible to a test suite that only reads.
--   4. User A CANNOT UPDATE user B's row (zero rows affected, not an
--      error — Postgres RLS filters UPDATE/DELETE targets via the USING
--      clause rather than raising).
--   5. User A CANNOT DELETE user B's row (zero rows affected).
--   6. The anonymous (unauthenticated) role gets zero rows.
--
-- Tables that are deliberately NOT per-user-owned (`product_candidates`,
-- `subscriptions`, `account_deletions`) get their own sections below that
-- assert their *intended* policy instead of the six checks above — see each
-- section's comment for what "correct" means for that table.
--
-- WHY THE CROSS-INSERT TARGET IS "USER C", NOT "USER B"
-- -------------------------------------------------------
-- Several tables have a uniqueness constraint keyed on `user_id`
-- (style_profiles, body_profiles, lifestyle_profiles: `unique(user_id)`) or
-- on `(user_id, ...)` (daily_briefs, occasions' calendar-sync index,
-- outfit_items' per-outfit uniqueness). User B already has a seeded fixture
-- row in every such table (needed for checks 2/4/5 above). If the
-- cross-insert attempt in check 3 also targeted `user_id = B`, a genuinely
-- broken `WITH CHECK` could still appear to "block" the insert — but for
-- the wrong reason (a unique-constraint violation, not RLS), which would
-- silently mask exactly the class of gap this suite exists to catch. A
-- third fixture identity, USER C, has zero pre-existing rows in any table,
-- so an insert attempt targeting it can only be blocked by RLS. The
-- assertion under test — "authenticated user A cannot INSERT a row whose
-- user_id is not their own" — is identical either way, since
-- `WITH CHECK (user_id = auth.uid())` does not special-case which other
-- user_id is used.
--
-- The three denormalized-user_id child tables (closet_item_images,
-- outfit_items, kyra_messages) are the exception: their cross-insert check
-- targets user B's real PARENT row (closet_item/outfit/thread) on purpose,
-- because what's actually under test there is the
-- set_user_id_from_*()-trigger family's own RLS-filtered lookup (see
-- 20260728101200_functions_and_triggers.sql section 3's comment), not a
-- plain WITH CHECK.
--
-- HOW USER IMPERSONATION WORKS
-- ------------------------------
-- `set role authenticated;` + `set request.jwt.claims = '{"sub": "<uuid>",
-- "role": "authenticated"}';` is exactly what PostgREST does per request;
-- supabase/tests/00_test_only_auth_storage_shim.sql's auth.uid()/auth.role()
-- read the claim back out, so every RLS predicate in
-- 20260728100900_rls_policies.sql resolves the same way it would for a real
-- request. All fixture seeding is done as the connecting superuser (which
-- owns every table and therefore bypasses RLS — see that migration's note
-- on ENABLE vs FORCE ROW LEVEL SECURITY), so seeding itself is never
-- filtered.
-- ============================================================================

-- NOTE: client_min_messages is deliberately left at its default ('notice'),
-- unlike the two setup files this one runs after — this file's RAISE NOTICE
-- calls (per-table progress markers, the final summary) and RAISE WARNING
-- calls (pg_temp.record_result's immediate per-failure flag) ARE the
-- narrative output this suite exists to produce.

-- ============================================================================
-- SECTION 0 — Fixtures: users, id lookup helper, results table.
-- ============================================================================

-- Three real users (A, B) plus a deliberately "clean" third identity (C —
-- see header comment on why C, not B, is the cross-insert target) plus a
-- fourth (D) reserved solely for the `profiles` insert-block check (see that
-- section). Inserting into auth.users fires handle_new_user(), so each of
-- these also gets an automatic `profiles` row.
create or replace function pg_temp.user_a() returns uuid language sql immutable as
  $$ select '10000000-0000-0000-0000-000000000001'::uuid $$;
create or replace function pg_temp.user_b() returns uuid language sql immutable as
  $$ select '10000000-0000-0000-0000-000000000002'::uuid $$;
create or replace function pg_temp.user_c() returns uuid language sql immutable as
  $$ select '10000000-0000-0000-0000-000000000003'::uuid $$;
create or replace function pg_temp.user_d() returns uuid language sql immutable as
  $$ select '10000000-0000-0000-0000-000000000004'::uuid $$;

insert into auth.users (id, email) values
  (pg_temp.user_a(), 'user-a@rls-test.astrastyle.invalid'),
  (pg_temp.user_b(), 'user-b@rls-test.astrastyle.invalid'),
  (pg_temp.user_c(), 'user-c@rls-test.astrastyle.invalid'),
  (pg_temp.user_d(), 'user-d@rls-test.astrastyle.invalid');

-- Fixture row-id registry: label -> id, populated as each table is seeded
-- below and read back via pg_temp.fx() everywhere a later INSERT needs to
-- reference an earlier fixture row (e.g. outfit_items.a needs closet_items.a).
create temporary table fixture_ids (
  label text primary key,
  id    uuid not null
);

-- SECURITY DEFINER for the same reason as pg_temp.record_result() below:
-- Section 4 (product_candidates) calls fx() while impersonating
-- `authenticated`, which has no grant on this session's own fixture-id
-- bookkeeping table (nor should it).
create or replace function pg_temp.fx(p_label text) returns uuid
  language sql stable security definer as
  $$ select id from fixture_ids where label = p_label $$;

insert into fixture_ids (label, id) values
  ('profiles.a', pg_temp.user_a()),
  ('profiles.b', pg_temp.user_b());

-- USER D gets an auth.users row (so profiles.id's FK to auth.users is
-- satisfiable) but must NOT keep the profiles row handle_new_user() just
-- auto-created for it, or the profiles insert-block check below would be
-- masked by a primary-key collision instead of testing RLS. Every other
-- user's profiles row auto-created by the trigger IS a fixture we want to
-- keep (that's how profiles.a / profiles.b exist at all).
delete from public.profiles where id = pg_temp.user_d();

-- Results ledger. Every assertion in this file appends exactly one row.
create temporary table rls_results (
  seq         serial primary key,
  table_name  text not null,
  assertion   text not null,
  ok          boolean not null,
  detail      text
);

-- SECURITY DEFINER: assertions are recorded while impersonating
-- `authenticated`/`anon` (see check_owned_table below), neither of which has
-- — or should have — any grant on this session's own bookkeeping table.
-- Running as the definer (the connecting superuser that created
-- `rls_results`) is exactly the same pattern the app's own migrations use
-- for the same reason (see archive_closet_item() in
-- 20260728101200_functions_and_triggers.sql): the elevated privilege is
-- scoped to this one function body, not handed to the impersonated role.
create or replace function pg_temp.record_result(
  p_table text, p_assertion text, p_ok boolean, p_detail text default null
) returns void language plpgsql security definer as $$
begin
  insert into rls_results (table_name, assertion, ok, detail)
  values (p_table, p_assertion, p_ok, p_detail);
  if not p_ok then
    raise warning '[RLS FAIL] %: % — %', p_table, p_assertion, coalesce(p_detail, '');
  end if;
end;
$$;

-- ============================================================================
-- SECTION 1 — Generic six-assertion check for a standard owned table.
-- ============================================================================
-- p_cross_insert_sql is the one thing that has to vary per table (every
-- table has different NOT NULL columns); everything else (select-own,
-- select-other, cross-update, cross-delete, anon) is mechanically identical
-- given the table name, primary key column, and two fixture row ids, so it
-- is generated here rather than repeated 17 times.
create or replace procedure pg_temp.check_owned_table(
  p_table            text,
  p_pk               text,
  p_row_a            uuid,
  p_row_b            uuid,
  p_user_a           uuid,
  p_cross_insert_sql text
) language plpgsql as $$
declare
  v_exists   boolean;
  v_rowcount int;
  v_blocked  boolean;
  v_detail   text;
begin
  raise notice '--- % ---', p_table;

  -- Impersonate user A: same `SET ROLE` + `request.jwt.claims` PostgREST
  -- sets per-request for a real authenticated call.
  execute 'set role authenticated';
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_a, 'role', 'authenticated')::text,
    false
  );

  -- 1. A can SELECT their own row.
  execute format('select exists(select 1 from %I where %I = %L)', p_table, p_pk, p_row_a) into v_exists;
  perform pg_temp.record_result(p_table, 'A can SELECT own row', v_exists);

  -- 2. A gets zero rows selecting B's row (not an error).
  execute format('select exists(select 1 from %I where %I = %L)', p_table, p_pk, p_row_b) into v_exists;
  perform pg_temp.record_result(p_table, 'A gets zero rows selecting B''s row', not v_exists);

  -- 3. A cannot INSERT a row for another user.
  begin
    execute p_cross_insert_sql;
    v_blocked := false;
    v_detail := 'INSERT SUCCEEDED — this is an RLS GAP (missing/incorrect WITH CHECK)';
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result(p_table, 'A cannot INSERT a row for another user', v_blocked, v_detail);

  -- 4. A cannot UPDATE B's row (zero rows affected).
  execute format('update %I set updated_at = now() where %I = %L', p_table, p_pk, p_row_b);
  get diagnostics v_rowcount = row_count;
  perform pg_temp.record_result(
    p_table, 'A cannot UPDATE B''s row', v_rowcount = 0, format('%s row(s) affected', v_rowcount)
  );

  -- 5. A cannot DELETE B's row (zero rows affected).
  execute format('delete from %I where %I = %L', p_table, p_pk, p_row_b);
  get diagnostics v_rowcount = row_count;
  perform pg_temp.record_result(
    p_table, 'A cannot DELETE B''s row', v_rowcount = 0, format('%s row(s) affected', v_rowcount)
  );

  execute 'reset role';

  -- 6. Anonymous role gets zero rows — no policy in this schema is granted
  -- `to anon` anywhere, so this should hold regardless of claims content;
  -- clear the claim anyway so the check is not accidentally relying on A's
  -- leftover session state.
  execute 'set role anon';
  perform set_config('request.jwt.claims', '', false);
  execute format('select exists(select 1 from %I where %I in (%L, %L))', p_table, p_pk, p_row_a, p_row_b)
    into v_exists;
  perform pg_temp.record_result(p_table, 'anonymous role gets zero rows', not v_exists);

  execute 'reset role';
end;
$$;

-- ============================================================================
-- SECTION 2 — Fixture seeding (as the connecting superuser; bypasses RLS).
-- ============================================================================

-- style_profiles / body_profiles / lifestyle_profiles (1:1 with a user)
with ins as (insert into style_profiles (user_id) values (pg_temp.user_a()) returning id)
  insert into fixture_ids select 'style_profiles.a', id from ins;
with ins as (insert into style_profiles (user_id) values (pg_temp.user_b()) returning id)
  insert into fixture_ids select 'style_profiles.b', id from ins;

with ins as (insert into body_profiles (user_id) values (pg_temp.user_a()) returning id)
  insert into fixture_ids select 'body_profiles.a', id from ins;
with ins as (insert into body_profiles (user_id) values (pg_temp.user_b()) returning id)
  insert into fixture_ids select 'body_profiles.b', id from ins;

with ins as (insert into lifestyle_profiles (user_id) values (pg_temp.user_a()) returning id)
  insert into fixture_ids select 'lifestyle_profiles.a', id from ins;
with ins as (insert into lifestyle_profiles (user_id) values (pg_temp.user_b()) returning id)
  insert into fixture_ids select 'lifestyle_profiles.b', id from ins;

-- closet_items
with ins as (insert into closet_items (user_id, category) values (pg_temp.user_a(), 'top') returning id)
  insert into fixture_ids select 'closet_items.a', id from ins;
with ins as (insert into closet_items (user_id, category) values (pg_temp.user_b(), 'top') returning id)
  insert into fixture_ids select 'closet_items.b', id from ins;

-- closet_item_images (user_id is denormalized/trigger-populated from closet_item_id)
with ins as (
  insert into closet_item_images (closet_item_id, storage_path)
  values (pg_temp.fx('closet_items.a'), 'users/fixture-a/closet/img.jpg')
  returning id
) insert into fixture_ids select 'closet_item_images.a', id from ins;
with ins as (
  insert into closet_item_images (closet_item_id, storage_path)
  values (pg_temp.fx('closet_items.b'), 'users/fixture-b/closet/img.jpg')
  returning id
) insert into fixture_ids select 'closet_item_images.b', id from ins;

-- outfits
with ins as (insert into outfits (user_id) values (pg_temp.user_a()) returning id)
  insert into fixture_ids select 'outfits.a', id from ins;
with ins as (insert into outfits (user_id) values (pg_temp.user_b()) returning id)
  insert into fixture_ids select 'outfits.b', id from ins;

-- product_candidates: one SHARED row, no owner (see SECTION 4).
with ins as (
  insert into product_candidates (canonical_url, name)
  values ('https://retailer.example.invalid/rls-fixture-product', 'RLS Fixture Product')
  returning id
) insert into fixture_ids select 'product_candidates.shared', id from ins;

-- outfit_items (user_id denormalized from outfit_id; role reuses clothing_category)
with ins as (
  insert into outfit_items (outfit_id, closet_item_id, role)
  values (pg_temp.fx('outfits.a'), pg_temp.fx('closet_items.a'), 'top')
  returning id
) insert into fixture_ids select 'outfit_items.a', id from ins;
with ins as (
  insert into outfit_items (outfit_id, closet_item_id, role)
  values (pg_temp.fx('outfits.b'), pg_temp.fx('closet_items.b'), 'top')
  returning id
) insert into fixture_ids select 'outfit_items.b', id from ins;

-- outfit_wears (user_id is a direct, non-denormalized column here)
with ins as (
  insert into outfit_wears (outfit_id, user_id) values (pg_temp.fx('outfits.a'), pg_temp.user_a()) returning id
) insert into fixture_ids select 'outfit_wears.a', id from ins;
with ins as (
  insert into outfit_wears (outfit_id, user_id) values (pg_temp.fx('outfits.b'), pg_temp.user_b()) returning id
) insert into fixture_ids select 'outfit_wears.b', id from ins;

-- style_feedback (target_id is polymorphic/unconstrained by design — see migration comment)
with ins as (
  insert into style_feedback (user_id, target_type, target_id, signal)
  values (pg_temp.user_a(), 'outfit', pg_temp.fx('outfits.a'), 'like')
  returning id
) insert into fixture_ids select 'style_feedback.a', id from ins;
with ins as (
  insert into style_feedback (user_id, target_type, target_id, signal)
  values (pg_temp.user_b(), 'outfit', pg_temp.fx('outfits.b'), 'like')
  returning id
) insert into fixture_ids select 'style_feedback.b', id from ins;

-- style_memories
with ins as (
  insert into style_memories (user_id, memory_type, content)
  values (pg_temp.user_a(), 'preference', 'Prefers navy and charcoal.')
  returning id
) insert into fixture_ids select 'style_memories.a', id from ins;
with ins as (
  insert into style_memories (user_id, memory_type, content)
  values (pg_temp.user_b(), 'preference', 'Avoids logos.')
  returning id
) insert into fixture_ids select 'style_memories.b', id from ins;

-- kyra_threads
with ins as (insert into kyra_threads (user_id) values (pg_temp.user_a()) returning id)
  insert into fixture_ids select 'kyra_threads.a', id from ins;
with ins as (insert into kyra_threads (user_id) values (pg_temp.user_b()) returning id)
  insert into fixture_ids select 'kyra_threads.b', id from ins;

-- kyra_messages (user_id denormalized from thread_id)
with ins as (
  insert into kyra_messages (thread_id, role, content)
  values (pg_temp.fx('kyra_threads.a'), 'user', 'What should I wear tonight?')
  returning id
) insert into fixture_ids select 'kyra_messages.a', id from ins;
with ins as (
  insert into kyra_messages (thread_id, role, content)
  values (pg_temp.fx('kyra_threads.b'), 'user', 'What should I wear tonight?')
  returning id
) insert into fixture_ids select 'kyra_messages.b', id from ins;

-- occasions
with ins as (
  insert into occasions (user_id, title, starts_at)
  values (pg_temp.user_a(), 'Dinner', now() + interval '1 day')
  returning id
) insert into fixture_ids select 'occasions.a', id from ins;
with ins as (
  insert into occasions (user_id, title, starts_at)
  values (pg_temp.user_b(), 'Dinner', now() + interval '1 day')
  returning id
) insert into fixture_ids select 'occasions.b', id from ins;

-- daily_briefs (unique(user_id, brief_date) — same date, different user_id, no collision)
with ins as (
  insert into daily_briefs (user_id, brief_date) values (pg_temp.user_a(), current_date) returning id
) insert into fixture_ids select 'daily_briefs.a', id from ins;
with ins as (
  insert into daily_briefs (user_id, brief_date) values (pg_temp.user_b(), current_date) returning id
) insert into fixture_ids select 'daily_briefs.b', id from ins;

-- studio_generations
with ins as (insert into studio_generations (user_id) values (pg_temp.user_a()) returning id)
  insert into fixture_ids select 'studio_generations.a', id from ins;
with ins as (insert into studio_generations (user_id) values (pg_temp.user_b()) returning id)
  insert into fixture_ids select 'studio_generations.b', id from ins;

-- user_product_evaluations
with ins as (
  insert into user_product_evaluations (user_id, product_candidate_id, verdict)
  values (pg_temp.user_a(), pg_temp.fx('product_candidates.shared'), 'consider')
  returning id
) insert into fixture_ids select 'user_product_evaluations.a', id from ins;
with ins as (
  insert into user_product_evaluations (user_id, product_candidate_id, verdict)
  values (pg_temp.user_b(), pg_temp.fx('product_candidates.shared'), 'consider')
  returning id
) insert into fixture_ids select 'user_product_evaluations.b', id from ins;

-- subscriptions
with ins as (
  insert into subscriptions (user_id, app_store_original_transaction_id, product_id, status)
  values (pg_temp.user_a(), 'rls-fixture-txn-a', 'com.astrastyle.premium.monthly', 'active')
  returning id
) insert into fixture_ids select 'subscriptions.a', id from ins;
with ins as (
  insert into subscriptions (user_id, app_store_original_transaction_id, product_id, status)
  values (pg_temp.user_b(), 'rls-fixture-txn-b', 'com.astrastyle.premium.monthly', 'active')
  returning id
) insert into fixture_ids select 'subscriptions.b', id from ins;

-- account_deletions (seeded directly, bypassing the request_account_deletion()
-- RPC, because this suite is testing the table's raw RLS policies, not the RPC)
with ins as (insert into account_deletions (user_id, status) values (pg_temp.user_a(), 'pending') returning id)
  insert into fixture_ids select 'account_deletions.a', id from ins;
with ins as (insert into account_deletions (user_id, status) values (pg_temp.user_b(), 'pending') returning id)
  insert into fixture_ids select 'account_deletions.b', id from ins;

-- ============================================================================
-- SECTION 3 — Run the six-assertion check against every standard table.
-- ============================================================================

call pg_temp.check_owned_table('profiles', 'id', pg_temp.fx('profiles.a'), pg_temp.fx('profiles.b'), pg_temp.user_a(),
  format('insert into profiles (id, display_name) values (%L, %L)', pg_temp.user_d(), 'probe'));

call pg_temp.check_owned_table('style_profiles', 'id', pg_temp.fx('style_profiles.a'), pg_temp.fx('style_profiles.b'), pg_temp.user_a(),
  format('insert into style_profiles (user_id) values (%L)', pg_temp.user_c()));

call pg_temp.check_owned_table('body_profiles', 'id', pg_temp.fx('body_profiles.a'), pg_temp.fx('body_profiles.b'), pg_temp.user_a(),
  format('insert into body_profiles (user_id) values (%L)', pg_temp.user_c()));

call pg_temp.check_owned_table('lifestyle_profiles', 'id', pg_temp.fx('lifestyle_profiles.a'), pg_temp.fx('lifestyle_profiles.b'), pg_temp.user_a(),
  format('insert into lifestyle_profiles (user_id) values (%L)', pg_temp.user_c()));

call pg_temp.check_owned_table('closet_items', 'id', pg_temp.fx('closet_items.a'), pg_temp.fx('closet_items.b'), pg_temp.user_a(),
  format('insert into closet_items (user_id, category) values (%L, %L)', pg_temp.user_c(), 'top'));

-- closet_item_images: the interesting attack is "attach an image to B's
-- closet_item while acting as A" — user_id itself is trigger-populated and
-- cannot be set directly by the client at all (see SECTION 0/migration
-- comment), so the meaningful cross-insert target is B's real parent row,
-- not a synthetic USER C.
call pg_temp.check_owned_table('closet_item_images', 'id', pg_temp.fx('closet_item_images.a'), pg_temp.fx('closet_item_images.b'), pg_temp.user_a(),
  format('insert into closet_item_images (closet_item_id, storage_path) values (%L, %L)',
    pg_temp.fx('closet_items.b'), 'users/hack/probe.jpg'));

call pg_temp.check_owned_table('outfits', 'id', pg_temp.fx('outfits.a'), pg_temp.fx('outfits.b'), pg_temp.user_a(),
  format('insert into outfits (user_id) values (%L)', pg_temp.user_c()));

-- outfit_items: same "attach a slot to B's outfit" attack as
-- closet_item_images above. Uses the shared product_candidates row (not a
-- closet_item) as the slot's item so this insert cannot collide with the
-- unique(outfit_id, closet_item_id) index that outfit_items.b already
-- occupies.
call pg_temp.check_owned_table('outfit_items', 'id', pg_temp.fx('outfit_items.a'), pg_temp.fx('outfit_items.b'), pg_temp.user_a(),
  format('insert into outfit_items (outfit_id, product_candidate_id, role) values (%L, %L, %L)',
    pg_temp.fx('outfits.b'), pg_temp.fx('product_candidates.shared'), 'top'));

call pg_temp.check_owned_table('outfit_wears', 'id', pg_temp.fx('outfit_wears.a'), pg_temp.fx('outfit_wears.b'), pg_temp.user_a(),
  format('insert into outfit_wears (outfit_id, user_id) values (%L, %L)', pg_temp.fx('outfits.b'), pg_temp.user_c()));

call pg_temp.check_owned_table('style_feedback', 'id', pg_temp.fx('style_feedback.a'), pg_temp.fx('style_feedback.b'), pg_temp.user_a(),
  format('insert into style_feedback (user_id, target_type, target_id, signal) values (%L, %L, %L, %L)',
    pg_temp.user_c(), 'outfit', pg_temp.fx('outfits.a'), 'like'));

call pg_temp.check_owned_table('style_memories', 'id', pg_temp.fx('style_memories.a'), pg_temp.fx('style_memories.b'), pg_temp.user_a(),
  format('insert into style_memories (user_id, memory_type, content) values (%L, %L, %L)',
    pg_temp.user_c(), 'preference', 'probe'));

call pg_temp.check_owned_table('kyra_threads', 'id', pg_temp.fx('kyra_threads.a'), pg_temp.fx('kyra_threads.b'), pg_temp.user_a(),
  format('insert into kyra_threads (user_id) values (%L)', pg_temp.user_c()));

-- kyra_messages: same "attach a message to B's thread" attack.
call pg_temp.check_owned_table('kyra_messages', 'id', pg_temp.fx('kyra_messages.a'), pg_temp.fx('kyra_messages.b'), pg_temp.user_a(),
  format('insert into kyra_messages (thread_id, role, content) values (%L, %L, %L)',
    pg_temp.fx('kyra_threads.b'), 'user', 'probe'));

call pg_temp.check_owned_table('occasions', 'id', pg_temp.fx('occasions.a'), pg_temp.fx('occasions.b'), pg_temp.user_a(),
  format('insert into occasions (user_id, title, starts_at) values (%L, %L, %L)', pg_temp.user_c(), 'probe', now()));

call pg_temp.check_owned_table('daily_briefs', 'id', pg_temp.fx('daily_briefs.a'), pg_temp.fx('daily_briefs.b'), pg_temp.user_a(),
  format('insert into daily_briefs (user_id, brief_date) values (%L, %L)', pg_temp.user_c(), current_date));

call pg_temp.check_owned_table('studio_generations', 'id', pg_temp.fx('studio_generations.a'), pg_temp.fx('studio_generations.b'), pg_temp.user_a(),
  format('insert into studio_generations (user_id) values (%L)', pg_temp.user_c()));

call pg_temp.check_owned_table('user_product_evaluations', 'id', pg_temp.fx('user_product_evaluations.a'), pg_temp.fx('user_product_evaluations.b'), pg_temp.user_a(),
  format('insert into user_product_evaluations (user_id, product_candidate_id, verdict) values (%L, %L, %L)',
    pg_temp.user_c(), pg_temp.fx('product_candidates.shared'), 'consider'));

-- ============================================================================
-- SECTION 4 — product_candidates: shared catalog, NOT per-user isolated.
-- ============================================================================
-- Intended policy (see 20260728100900_rls_policies.sql): every authenticated
-- user can SELECT every row (it is a shared catalog, not user data — the
-- opposite of the other 19 tables); only service_role may write. So the
-- "correct" behavior here is deliberately NOT the six-assertion isolation
-- check above — asserting that shape would be asserting the wrong thing.
do $$
declare
  v_exists boolean;
  v_rowcount int;
  v_blocked boolean;
  v_detail text;
begin
  raise notice '--- product_candidates (shared catalog, not user-owned) ---';

  execute 'set role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.user_a(), 'role', 'authenticated')::text, false);
  select exists(select 1 from product_candidates where id = pg_temp.fx('product_candidates.shared')) into v_exists;
  perform pg_temp.record_result('product_candidates', 'user A can SELECT the shared catalog row', v_exists);
  execute 'reset role';

  execute 'set role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.user_b(), 'role', 'authenticated')::text, false);
  select exists(select 1 from product_candidates where id = pg_temp.fx('product_candidates.shared')) into v_exists;
  perform pg_temp.record_result('product_candidates', 'user B (different user) can ALSO SELECT it — it is shared, not isolated', v_exists);

  begin
    insert into product_candidates (canonical_url, name) values ('https://retailer.example.invalid/blocked', 'Blocked');
    v_blocked := false;
    v_detail := 'INSERT SUCCEEDED — authenticated users must not be able to write the catalog directly';
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('product_candidates', 'authenticated INSERT is blocked (service-role-write only)', v_blocked, v_detail);

  execute format('update product_candidates set updated_at = now() where id = %L', pg_temp.fx('product_candidates.shared'));
  get diagnostics v_rowcount = row_count;
  perform pg_temp.record_result('product_candidates', 'authenticated UPDATE is blocked (zero rows affected)', v_rowcount = 0,
    format('%s row(s) affected', v_rowcount));

  execute format('delete from product_candidates where id = %L', pg_temp.fx('product_candidates.shared'));
  get diagnostics v_rowcount = row_count;
  perform pg_temp.record_result('product_candidates', 'authenticated DELETE is blocked (zero rows affected)', v_rowcount = 0,
    format('%s row(s) affected', v_rowcount));

  execute 'reset role';

  execute 'set role anon';
  perform set_config('request.jwt.claims', '', false);
  select exists(select 1 from product_candidates where id = pg_temp.fx('product_candidates.shared')) into v_exists;
  perform pg_temp.record_result('product_candidates', 'anonymous role gets zero rows (policy is `to authenticated` only)', not v_exists);
  execute 'reset role';
end
$$;

-- ============================================================================
-- SECTION 5 — subscriptions: read-only to the owning user, service-role write.
-- ============================================================================
-- Intended policy: select-own only. No insert/update/delete policy is
-- granted to `authenticated` AT ALL — writes come only from
-- POST /subscriptions/sync and the App Store webhook, both service-role.
-- The generic check_owned_table already proves "A cannot write a row
-- claiming to be C"; the extra assertion below proves the stronger,
-- table-specific intent: A cannot write ANY row here, including one
-- correctly attributed to themselves — this table has no client-writable
-- path at all, by design.
call pg_temp.check_owned_table('subscriptions', 'id', pg_temp.fx('subscriptions.a'), pg_temp.fx('subscriptions.b'), pg_temp.user_a(),
  format('insert into subscriptions (user_id, app_store_original_transaction_id, product_id, status) values (%L, %L, %L, %L)',
    pg_temp.user_c(), 'rls-fixture-txn-c-cross', 'com.astrastyle.premium.monthly', 'active'));

do $$
declare
  v_blocked boolean;
  v_detail text;
begin
  execute 'set role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.user_a(), 'role', 'authenticated')::text, false);
  begin
    insert into subscriptions (user_id, app_store_original_transaction_id, product_id, status)
    values (pg_temp.user_a(), 'rls-fixture-txn-a-self', 'com.astrastyle.premium.monthly', 'active');
    v_blocked := false;
    v_detail := 'INSERT SUCCEEDED — subscriptions must be written only by service-role Edge Functions, even for one''s own user_id';
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('subscriptions', 'A cannot INSERT even a correctly-self-owned row (service-role-write only)', v_blocked, v_detail);
  execute 'reset role';
end
$$;

-- ============================================================================
-- SECTION 6 — account_deletions: select-own status polling, service-role write.
-- ============================================================================
-- Intended policy: select-own only, per 20260728101300_account_deletion.sql.
-- Rows are only ever written by request_account_deletion() (SECURITY
-- DEFINER, using auth.uid() internally — never a client-supplied user id)
-- and the service-role-only finalize/complete/failed functions. Same
-- extra-assertion rationale as subscriptions above: no direct client write
-- path should exist at all, self-owned or not.
call pg_temp.check_owned_table('account_deletions', 'id', pg_temp.fx('account_deletions.a'), pg_temp.fx('account_deletions.b'), pg_temp.user_a(),
  format('insert into account_deletions (user_id, status) values (%L, %L)', pg_temp.user_c(), 'pending'));

do $$
declare
  v_blocked boolean;
  v_detail text;
begin
  execute 'set role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.user_a(), 'role', 'authenticated')::text, false);
  begin
    insert into account_deletions (user_id, status) values (pg_temp.user_a(), 'pending');
    v_blocked := false;
    v_detail := 'INSERT SUCCEEDED — account_deletions rows must only be created via request_account_deletion(), never a direct client insert';
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('account_deletions', 'A cannot directly INSERT even a correctly-self-owned row (RPC-only write path)', v_blocked, v_detail);
  execute 'reset role';
end
$$;

-- ============================================================================
-- SECTION 7 — archive_closet_item() / restore_closet_item() RPCs.
-- ============================================================================
-- As of 20260730170000_narrow_security_definer_scope.sql these two run
-- SECURITY INVOKER (previously DEFINER), relying on closet_items' own RLS
-- UPDATE policy (`user_id = auth.uid()`) instead of bypassing it. This
-- section proves that narrowing didn't quietly break the RPCs' own
-- ownership/idempotency checks, and that both remain unreachable for a
-- caller who doesn't own the row, or isn't authenticated at all.
do $$
declare
  v_archived_at  timestamptz;
  v_availability text;
  v_blocked      boolean;
  v_detail       text;
begin
  raise notice '--- archive_closet_item() / restore_closet_item() ---';

  execute 'set role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.user_a(), 'role', 'authenticated')::text, false);

  -- 1. A can archive their own item.
  begin
    perform public.archive_closet_item(pg_temp.fx('closet_items.a'));
    v_blocked := false;
    v_detail := null;
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('archive_closet_item', 'A can archive own closet item', not v_blocked, v_detail);

  select archived_at, availability_state::text into v_archived_at, v_availability
    from closet_items where id = pg_temp.fx('closet_items.a');
  perform pg_temp.record_result('archive_closet_item', 'archived_at set and availability_state = unavailable',
    v_archived_at is not null and v_availability = 'unavailable',
    format('archived_at=%s availability_state=%s', v_archived_at, v_availability));

  -- 2. Archiving an already-archived item raises (idempotency guard), not a silent no-op.
  begin
    perform public.archive_closet_item(pg_temp.fx('closet_items.a'));
    v_blocked := false;
    v_detail := 'archiving an already-archived item SUCCEEDED — idempotency guard is gone';
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('archive_closet_item', 'A cannot re-archive an already-archived item', v_blocked, v_detail);

  -- 3. A cannot archive B's item. This is the assertion that actually
  -- exercises the SECURITY INVOKER change: under DEFINER this was enforced
  -- solely by the function's own WHERE clause; under INVOKER it's now
  -- enforced by both that WHERE clause AND closet_items' RLS update policy.
  begin
    perform public.archive_closet_item(pg_temp.fx('closet_items.b'));
    v_blocked := false;
    v_detail := 'archiving B''s item SUCCEEDED — this is a cross-user write bug';
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('archive_closet_item', 'A cannot archive B''s closet item', v_blocked, v_detail);

  -- 4. A can restore their own (now-archived) item.
  begin
    perform public.restore_closet_item(pg_temp.fx('closet_items.a'));
    v_blocked := false;
    v_detail := null;
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('restore_closet_item', 'A can restore own closet item', not v_blocked, v_detail);

  select archived_at, availability_state::text into v_archived_at, v_availability
    from closet_items where id = pg_temp.fx('closet_items.a');
  perform pg_temp.record_result('restore_closet_item', 'archived_at cleared and availability_state = available',
    v_archived_at is null and v_availability = 'available',
    format('archived_at=%s availability_state=%s', v_archived_at, v_availability));

  -- 5. A cannot restore B's item.
  begin
    perform public.restore_closet_item(pg_temp.fx('closet_items.b'));
    v_blocked := false;
    v_detail := 'restoring B''s item SUCCEEDED — this is a cross-user write bug';
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('restore_closet_item', 'A cannot restore B''s closet item', v_blocked, v_detail);

  execute 'reset role';

  -- 6. Neither RPC is reachable by the anonymous role at all (no EXECUTE grant).
  execute 'set role anon';
  perform set_config('request.jwt.claims', '', false);

  begin
    perform public.archive_closet_item(pg_temp.fx('closet_items.a'));
    v_blocked := false;
    v_detail := 'anon call SUCCEEDED — EXECUTE grant is missing its restriction to authenticated';
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('archive_closet_item', 'anonymous role cannot call archive_closet_item at all', v_blocked, v_detail);

  begin
    perform public.restore_closet_item(pg_temp.fx('closet_items.a'));
    v_blocked := false;
    v_detail := 'anon call SUCCEEDED — EXECUTE grant is missing its restriction to authenticated';
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('restore_closet_item', 'anonymous role cannot call restore_closet_item at all', v_blocked, v_detail);

  execute 'reset role';
end
$$;

-- ============================================================================
-- SECTION 8 — request_account_deletion() RPC (deliberately still SECURITY
-- DEFINER — see 20260730170000_narrow_security_definer_scope.sql).
-- ============================================================================
-- SECTION 6 above already proves account_deletions has no direct client
-- INSERT path. This section proves the other half: the one sanctioned write
-- path — this RPC — still works, is still confined to the caller's own
-- user_id, and still enforces "one in-flight deletion per user". User C is
-- used for the success path (not A/B) because both already have a seeded
-- 'pending' account_deletions fixture row from SECTION 2, which would
-- otherwise make every call here hit the "already in progress" branch
-- instead of exercising the plain success path.
do $$
declare
  v_new_id       uuid;
  v_row_user_id  uuid;
  v_row_status   text;
  v_blocked      boolean;
  v_detail       text;
begin
  raise notice '--- request_account_deletion() ---';

  -- 1. User A, who already has a pending fixture row (SECTION 2), gets the
  -- "already in progress" guard rather than a second row.
  execute 'set role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.user_a(), 'role', 'authenticated')::text, false);
  begin
    perform public.request_account_deletion();
    v_blocked := false;
    v_detail := 'second call for A SUCCEEDED — "one deletion in progress per user" guard is gone';
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('request_account_deletion', 'A cannot request a second deletion while one is pending', v_blocked, v_detail);
  execute 'reset role';

  -- 2. User C (no pre-existing account_deletions row) succeeds, and the
  -- resulting row is attributed to C — auth.uid(), not a client-supplied id.
  execute 'set role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.user_c(), 'role', 'authenticated')::text, false);
  begin
    select public.request_account_deletion() into v_new_id;
    v_blocked := false;
    v_detail := null;
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('request_account_deletion', 'C (no pending deletion) can request one', not v_blocked, v_detail);

  if v_new_id is not null then
    select user_id, status::text into v_row_user_id, v_row_status
      from account_deletions where id = v_new_id;
    perform pg_temp.record_result('request_account_deletion', 'resulting row is attributed to the caller (C), status pending',
      v_row_user_id = pg_temp.user_c() and v_row_status = 'pending',
      format('user_id=%s status=%s', v_row_user_id, v_row_status));

    -- 3. C can immediately see that row via the select-own policy (SECTION
    -- 6's generic check already covers this shape, but confirming it here
    -- ties the RPC's own output directly to the read path a client would
    -- actually use after calling it).
    perform pg_temp.record_result('request_account_deletion', 'C can SELECT the row the RPC just created',
      exists(select 1 from account_deletions where id = v_new_id));
  else
    perform pg_temp.record_result('request_account_deletion', 'resulting row is attributed to the caller (C), status pending', false, 'RPC did not return an id');
  end if;
  execute 'reset role';

  -- 4. The anonymous role cannot call this RPC at all (no EXECUTE grant, and
  -- auth.uid() would be null for it regardless).
  execute 'set role anon';
  perform set_config('request.jwt.claims', '', false);
  begin
    perform public.request_account_deletion();
    v_blocked := false;
    v_detail := 'anon call SUCCEEDED — EXECUTE grant is missing its restriction to authenticated';
  exception when others then
    v_blocked := true;
    v_detail := sqlerrm;
  end;
  perform pg_temp.record_result('request_account_deletion', 'anonymous role cannot call request_account_deletion at all', v_blocked, v_detail);
  execute 'reset role';
end
$$;

-- ============================================================================
-- SECTION 9 — Summary. Non-zero exit (via RAISE EXCEPTION) if anything failed.
-- ============================================================================

-- Defensive: every section above already resets its own role, but make sure
-- the summary query itself always runs as the connecting superuser
-- regardless of what came before.
reset role;

select
  table_name,
  assertion,
  case when ok then 'PASS' else 'FAIL' end as result,
  detail
from rls_results
order by seq;

do $$
declare
  v_total  int;
  v_failed int;
  v_tables int;
begin
  select count(*), count(*) filter (where not ok), count(distinct table_name)
    into v_total, v_failed, v_tables
    from rls_results;

  raise notice '================================================================';
  raise notice 'RLS ISOLATION SUITE: % assertion(s) across % table(s) — % passed, % failed',
    v_total, v_tables, v_total - v_failed, v_failed;
  raise notice '================================================================';

  if v_failed > 0 then
    raise exception '% RLS assertion(s) FAILED (see rows with result = FAIL above). This is a real Row Level Security gap — do not merge.', v_failed;
  end if;
end
$$;
