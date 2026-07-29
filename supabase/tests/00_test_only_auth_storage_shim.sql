-- ============================================================================
-- TEST-ONLY SHIM — supabase/tests/00_test_only_auth_storage_shim.sql
-- ============================================================================
-- DO NOT apply this file to any real Supabase project (hosted or
-- `supabase start`). Real Supabase projects already provide everything this
-- file fakes: the `auth`/`storage` schemas, `auth.users`, `auth.uid()`, the
-- `anon`/`authenticated`/`service_role` roles, and PostgREST's per-request
-- JWT-claim GUCs.
--
-- WHY THIS EXISTS
-- ----------------
-- `supabase/migrations/*.sql` assumes all of the above already exists (e.g.
-- `references auth.users(id)`, `auth.uid()` in every RLS policy). A bare
-- `postgres:16` instance — this container, or the `postgres`/
-- `pgvector/pgvector:pg16` service container `.github/workflows/rls-tests.yml`
-- spins up for CI — has none of it. This file creates just enough of a
-- stand-in to:
--   1. let every migration in supabase/migrations/ apply cleanly against a
--      vanilla Postgres 16 + pgvector instance, and
--   2. let supabase/tests/20_rls_isolation_tests.sql impersonate "a request
--      authenticated as user X" the same way PostgREST does for real:
--      `set role authenticated;` + `set request.jwt.claims = '{"sub": "...",
--      "role": "authenticated"}';`, which `auth.uid()` below reads back out.
--
-- This file is applied ONLY by scripts/run-rls-tests.sh, against a scratch
-- database, immediately before the real migrations. It is never referenced
-- by supabase/migrations/, by scripts/apply-migrations.sh, or by any
-- workflow that touches a real Supabase project. It does not belong in
-- supabase/migrations/ itself — migrations are append-only and describe real
-- schema changes (CLAUDE.md); this is test scaffolding, not a schema change.
--
-- What this deliberately does NOT try to fake: GoTrue's signup flow, JWT
-- signature verification, PostgREST's HTTP layer, or Storage's actual blob
-- backend. The RLS test suite only needs the SQL-visible surface — roles,
-- `auth.uid()`, and the `storage.objects`/`storage.foldername()` shapes the
-- migrations reference — not a running auth/storage service.
-- ============================================================================

set client_min_messages = warning;

-- ----------------------------------------------------------------------------
-- Roles. Real Supabase: anon/authenticated/service_role are pre-created,
-- login-less roles that PostgREST switches into per-request via `SET ROLE`
-- after verifying the request's JWT. `service_role` is BYPASSRLS (mirrors
-- the real platform default noted in 20260728100900_rls_policies.sql's
-- header comment: "service_role bypasses RLS entirely per Supabase platform
-- default").
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end
$$;

-- ----------------------------------------------------------------------------
-- auth schema
-- ----------------------------------------------------------------------------
create schema if not exists auth;

-- Minimal stand-in for GoTrue's auth.users. Real columns not needed by any
-- migration or test here (encrypted_password, confirmed_at, identities, ...)
-- are omitted on purpose — this is not a GoTrue reimplementation.
create table if not exists auth.users (
  id                  uuid primary key default gen_random_uuid(),
  email               text,
  raw_user_meta_data  jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now()
);

-- auth.uid() / auth.role(): read back the JWT claims a caller sets via
-- `set request.jwt.claims`, exactly like the real functions Supabase
-- installs. See https://supabase.com/docs/guides/database/postgres/row-level-security
-- "Testing your policies" for this exact pattern.
create or replace function auth.uid() returns uuid
  language sql stable
  as $$
    select nullif(
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'),
      ''
    )::uuid
  $$;

create or replace function auth.role() returns text
  language sql stable
  as $$
    select nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
  $$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
grant execute on function auth.role() to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- storage schema
-- ----------------------------------------------------------------------------
-- Minimal stand-in for Supabase Storage's metadata tables, sufficient for
-- 20260728101000_storage_buckets.sql to run its bucket-creation and
-- storage.objects RLS-policy statements instead of skipping them (that
-- migration's own `to_regclass('storage.buckets') is null` guard exists
-- specifically for environments without a storage schema at all — creating
-- one here means it gets exercised rather than skipped).
create schema if not exists storage;

create table if not exists storage.buckets (
  id                  text primary key,
  name                text not null,
  public              boolean not null default false,
  file_size_limit     bigint,
  allowed_mime_types  text[],
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table if not exists storage.objects (
  id           uuid primary key default gen_random_uuid(),
  bucket_id    text references storage.buckets(id),
  name         text,
  owner        uuid,
  metadata     jsonb,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Real implementation from the Supabase Storage extension: splits an object
-- path on "/" and drops the last segment (the file name itself), leaving
-- just the folder path components — e.g. 'users/<uid>/closet/img.jpg' ->
-- {users,<uid>,closet}. The storage.objects RLS policies in
-- 20260728101000_storage_buckets.sql index into this with
-- `(storage.foldername(name))[1]` / `[2]`.
create or replace function storage.foldername(name text)
  returns text[]
  language plpgsql
  immutable
  as $$
  declare
    _parts text[];
  begin
    select string_to_array(name, '/') into _parts;
    return _parts[1 : greatest(array_length(_parts, 1) - 1, 0)];
  end;
  $$;

grant usage on schema storage to anon, authenticated, service_role;
grant select on storage.buckets to anon, authenticated;
grant select, insert, update, delete on storage.objects to anon, authenticated;
