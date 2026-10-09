-- Optional owner-private, deterministic small variants for Closet grid tiles.
-- Existing rows remain valid and keep their full-resolution display/provider
-- paths. Guest photo bytes and paths resolve only on-device until linking; their
-- owner-scoped closet metadata remains associated with the anonymous user ID.

alter table public.closet_item_images
  add column thumbnail_storage_path text,
  add column background_removed_thumbnail_path text;

-- Thumbnail path must be the deterministic `.thumb.<same-format>` sibling of
-- its source, under that row's owner namespace. Guest-local metadata paths are
-- valid, but guest object bytes remain on-device (Storage RLS is tested separately).
-- No public URL or transform query is stored.
alter table public.closet_item_images
  add constraint closet_item_images_thumbnail_owner_shape_check check (
    thumbnail_storage_path is null or (
      thumbnail_storage_path = regexp_replace(storage_path, '\.(jpg|png)$', '.thumb.\1')
      and (
        storage_path ~ (
          '^users/' || user_id::text || '/closet/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(-cutout)?\.(jpg|png)|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(-cutout)?\.(jpg|png))$'
        )
        or storage_path ~ (
          '^guest-local/' || user_id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png)$'
        )
      )
    )
  ),
  add constraint closet_item_images_background_thumbnail_owner_shape_check check (
    background_removed_thumbnail_path is null or (
      background_removed_path is not null
      and background_removed_thumbnail_path = regexp_replace(background_removed_path, '\.(jpg|png)$', '.thumb.\1')
      and (
        background_removed_path ~ (
          '^users/' || user_id::text || '/closet/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-cutout\.png$'
        )
        or background_removed_path ~ (
          '^users/' || user_id::text || '/closet/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.png|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.png)$'
        )
        or background_removed_path ~ (
          '^guest-local/' || user_id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.png$'
        )
      )
    )
  );

comment on column public.closet_item_images.thumbnail_storage_path is
  'Optional private 660px-or-smaller, on-device generated grid rendition for storage_path. Original remains the provider/detail image.';
comment on column public.closet_item_images.background_removed_thumbnail_path is
  'Optional private small transparent rendition for background_removed_path. It is display-only; provider requests retain the original cutout.';
