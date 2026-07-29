-- ============================================================================
-- TEST-ONLY — supabase/tests/10_test_only_grants.sql
-- ============================================================================
-- DO NOT apply this file to any real Supabase project. Runs AFTER
-- supabase/migrations/*.sql (so the tables it grants on already exist) and
-- BEFORE supabase/tests/20_rls_isolation_tests.sql.
--
-- WHY THIS EXISTS
-- ----------------
-- Row Level Security policies are not the only access-control layer —
-- Postgres also requires the ordinary table-level GRANT (SELECT/INSERT/
-- UPDATE/DELETE) before RLS even gets consulted. On a real Supabase project
-- this baseline grant to `anon`/`authenticated` is applied automatically at
-- project bootstrap (Supabase's own internal setup, not something this
-- repo's migrations do — hence there is no migration file for it here).
-- Without an equivalent grant in this scratch test database, every query in
-- the RLS suite would fail with "permission denied for table X" before RLS
-- had a chance to filter anything, which would make the whole suite
-- vacuously fail (or, more dangerously, vacuously pass if the test harness
-- mistook "permission denied" for "RLS correctly blocked this") for the
-- wrong reason. This file exists so the RLS *policies* are what's actually
-- under test, not table-level grants.
-- ============================================================================

set client_min_messages = warning;

grant usage on schema public to anon, authenticated;

-- Broad DML grant, matching the real platform default described above. RLS
-- (enabled per-table in 20260728100900_rls_policies.sql and
-- 20260728101300_account_deletion.sql) is what actually restricts row
-- visibility/mutation from here — see that migration's own header comment.
grant select, insert, update, delete on all tables in schema public to anon, authenticated;

-- No sequences to grant: every table in this schema uses
-- `gen_random_uuid()` defaults, not serial/identity columns.
