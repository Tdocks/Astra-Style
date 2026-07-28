-- ============================================================================
-- Astra Style — 11. Storage buckets & storage RLS
-- ============================================================================
-- §15 gives one path convention across three feature areas:
--   users/{user_id}/closet/...
--   users/{user_id}/references/...
--   users/{user_id}/studio/...
-- The path is written with a shared `users/{user_id}/...` prefix rather than
-- three independent `{user_id}/...` prefixes, which we read as one bucket
-- with feature subfolders rather than three separate buckets. We create a
-- single private bucket, "user-content", and enforce the path convention via
-- storage.objects RLS policies keyed on `(storage.foldername(name))[1] =
-- 'users'` and `[2] = auth.uid()`. See docs/04-data-model.md "Ambiguities
-- resolved" for the alternative (three buckets) considered and why the single
-- bucket was chosen.
--
-- This migration only runs its storage.* statements if the `storage` schema
-- is present (i.e. a real Supabase project — hosted or the Supabase CLI local
-- stack). This keeps the migration from hard-failing when it is applied, for
-- schema-only testing purposes, against a vanilla Postgres instance that has
-- no Storage extension installed.
-- ============================================================================

set search_path = public, extensions;

do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage.buckets not found (not a Supabase project) — skipping bucket/storage-RLS setup.';
    return;
  end if;

  -- Idempotent bucket creation.
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values (
    'user-content',
    'user-content',
    false, -- private: all access via signed URLs (§15 "Keep buckets private")
    26214400, -- 25 MiB per object
    array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']
  )
  on conflict (id) do nothing;
end
$$;

-- ----------------------------------------------------------------------------
-- storage.objects RLS policies for the user-content bucket.
-- ----------------------------------------------------------------------------
-- Postgres has no `create policy if not exists`, so we guard each with a
-- pg_policies existence check instead of the duplicate_object exception idiom
-- used for enums (CREATE POLICY does not raise duplicate_object).
do $$
begin
  if to_regclass('storage.objects') is null then
    return;
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'user_content_select_own'
  ) then
    create policy user_content_select_own on storage.objects
      for select to authenticated
      using (
        bucket_id = 'user-content'
        and (storage.foldername(name))[1] = 'users'
        and (storage.foldername(name))[2] = (select auth.uid())::text
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'user_content_insert_own'
  ) then
    create policy user_content_insert_own on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'user-content'
        and (storage.foldername(name))[1] = 'users'
        and (storage.foldername(name))[2] = (select auth.uid())::text
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'user_content_update_own'
  ) then
    create policy user_content_update_own on storage.objects
      for update to authenticated
      using (
        bucket_id = 'user-content'
        and (storage.foldername(name))[1] = 'users'
        and (storage.foldername(name))[2] = (select auth.uid())::text
      )
      with check (
        bucket_id = 'user-content'
        and (storage.foldername(name))[1] = 'users'
        and (storage.foldername(name))[2] = (select auth.uid())::text
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'user_content_delete_own'
  ) then
    create policy user_content_delete_own on storage.objects
      for delete to authenticated
      using (
        bucket_id = 'user-content'
        and (storage.foldername(name))[1] = 'users'
        and (storage.foldername(name))[2] = (select auth.uid())::text
      );
  end if;
end
$$;

-- Expected object path shapes under this bucket (enforced by app/Edge
-- Function code, illustrated here for reference):
--   users/{user_id}/closet/{closet_item_id}/{image_id}.jpg
--   users/{user_id}/references/{reference_id}.jpg
--   users/{user_id}/studio/{studio_generation_id}.jpg
