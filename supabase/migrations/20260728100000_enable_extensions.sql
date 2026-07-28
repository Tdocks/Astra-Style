-- ============================================================================
-- Astra Style — 01. Extensions
-- ============================================================================
-- Supabase hosted projects and the Supabase CLI local stack both pre-provision
-- a dedicated "extensions" schema and put it on every database role's
-- search_path. We create it defensively (IF NOT EXISTS) so this migration is
-- also safe to run against a vanilla Postgres instance used for CI/testing.
-- ============================================================================

create schema if not exists extensions;

-- pgcrypto
-- gen_random_uuid() has been a Postgres 13+ built-in (no extension required),
-- but pgcrypto also provides digest()/hmac(), which the account-deletion audit
-- trail uses to store a one-way hash of a deleted user's id instead of the
-- raw id (see 20260728101300_account_deletion.sql).
create extension if not exists pgcrypto with schema extensions;

-- vector (pgvector)
-- Backs every embedding column: style_profiles.embedding, closet_items.embedding,
-- outfits.embedding, style_memories.embedding. See docs/04-data-model.md for the
-- chosen dimension (1536) and why changing it later requires a full rewrite.
create extension if not exists vector with schema extensions;

-- pg_trgm
-- Trigram indexes power fuzzy/ILIKE search over closet_items.name/brand and
-- product_candidates.name/brand (search bar in §6.14 Closet overview and the
-- product-link/search flows in §6.19/§6.21).
create extension if not exists pg_trgm with schema extensions;

-- unaccent
-- Normalizes accented brand/city/name text (e.g. "Zegna" vs "Žegna") ahead of
-- trigram search so accented and unaccented queries match the same rows.
create extension if not exists unaccent with schema extensions;

-- Make sure "extensions" is on this database's default search_path so that
-- unqualified references (vector, gen_random_uuid(), gin_trgm_ops) resolve for
-- every future session/migration, not just this one. Supabase hosted/local
-- projects already configure this; the guard makes the migration
-- self-sufficient against a plain Postgres instance too, where the migration
-- role may not have ALTER DATABASE privileges.
do $$
begin
  execute format('alter database %I set search_path = public, extensions', current_database());
exception
  when insufficient_privilege then
    raise notice 'Skipped ALTER DATABASE search_path (insufficient privilege). Ensure "extensions" is on search_path for this session/role manually.';
end
$$;

-- Apply for the remainder of this migration session too.
set search_path = public, extensions;
