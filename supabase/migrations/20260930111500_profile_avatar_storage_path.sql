-- Store a durable private Storage path for the user's optional profile photo.
-- Signed URLs expire and must not be persisted as identity data.
alter table public.profiles
  add column if not exists avatar_storage_path text;

comment on column public.profiles.avatar_storage_path is
  'Private user-content Storage path for the optional profile portrait; resolve to a short-lived signed URL at display time.';

-- Avatar images use the same private, caller-owned Storage bucket as the
-- user's closet and reference photos, at users/{user_id}/avatars/{avatar_id}.jpg.

alter table public.profiles
  add constraint profiles_avatar_storage_path_owner_shape_check
  check (
    avatar_storage_path is null
    or avatar_storage_path ~ ('^users/' || id::text || '/avatars/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$')
  );
