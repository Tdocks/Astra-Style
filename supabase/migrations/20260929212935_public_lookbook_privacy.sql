-- =============================================================================
-- Public lookbooks: allow intentional sharing without exposing private closet data.
-- =============================================================================
-- The original public-look policies queried outfit_wears under the requesting
-- user's RLS, so another user's wear row was invisible and every public look
-- failed its own visibility check. They also granted row-wide SELECT on
-- closet_items, which includes purchase, sizing, laundry, and wear-history data.
--
-- Public lookbooks now use a private SECURITY DEFINER predicate to establish
-- that a look is currently public, active, and has been worn. Peer garment data
-- is returned through a narrow invoker RPC that includes only fields needed to
-- render the shared look. Raw closet/image rows remain owner-only. An
-- authenticated Edge Function signs only the selected display image after
-- this RPC confirms the public worn outfit; when a cut-out exists, it never
-- signs the original photo.
-- =============================================================================

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create or replace function private.is_public_worn_outfit(p_outfit_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select auth.uid()) is not null
    and exists (
      select 1
      from public.outfits o
      where o.id = p_outfit_id
        and o.visibility = 'public'
        and o.archived_at is null
        and exists (
          select 1
          from public.outfit_wears w
          where w.outfit_id = o.id
        )
    ),
    false
  );
$$;

revoke all on function private.is_public_worn_outfit(uuid) from public, anon, authenticated;
grant execute on function private.is_public_worn_outfit(uuid) to authenticated;

comment on function private.is_public_worn_outfit(uuid) is
  'Internal RLS predicate. Bypasses child-table RLS only to verify a signed-in caller may view an opted-in, active outfit with wear history; not exposed through the Data API.';

-- Do not expose the raw outfits row to peers either: it includes the owner's
-- stable user id, favorite state, timestamps, hero URLs, and embedding. A
-- narrow summary RPC serves Discover and public look detail.
drop policy if exists outfits_select_public_worn on public.outfits;

create or replace function private.fetch_public_worn_looks(p_outfit_ids uuid[])
returns table (
  id uuid,
  name text,
  description text,
  occasion_tags jsonb,
  weather_min_celsius numeric,
  weather_max_celsius numeric,
  formality_score smallint,
  compatibility_score smallint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    o.id,
    coalesce(nullif(btrim(o.name), ''), 'A worn look') as name,
    o.description,
    o.occasion_tags,
    o.weather_min_celsius,
    o.weather_max_celsius,
    o.formality_score,
    o.compatibility_score
  from public.outfits o
  where (select auth.uid()) is not null
    and o.user_id <> (select auth.uid())
    and private.is_public_worn_outfit(o.id)
    and (
      coalesce(cardinality(p_outfit_ids), 0) = 0
      or o.id = any(p_outfit_ids)
    )
  order by o.updated_at desc
  limit 40;
$$;

revoke all on function private.fetch_public_worn_looks(uuid[]) from public, anon, authenticated;
grant execute on function private.fetch_public_worn_looks(uuid[]) to authenticated;

comment on function private.fetch_public_worn_looks(uuid[]) is
  'Returns only the summary fields needed to render another user''s active, public, worn look. Never returns owner ids, favorite state, timestamps, hero URLs, or embeddings.';

create or replace function public.fetch_public_worn_looks(p_outfit_ids uuid[])
returns table (
  id uuid,
  name text,
  description text,
  occasion_tags jsonb,
  weather_min_celsius numeric,
  weather_max_celsius numeric,
  formality_score smallint,
  compatibility_score smallint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.fetch_public_worn_looks(p_outfit_ids);
$$;

revoke all on function public.fetch_public_worn_looks(uuid[]) from public, anon, authenticated;
grant execute on function public.fetch_public_worn_looks(uuid[]) to authenticated;

-- Do not expose outfit_items, closet_items, or closet_item_images as full rows
-- to another user. Public garment display uses fetch_public_look_garments().
drop policy if exists outfit_items_select_public_look on public.outfit_items;
drop policy if exists closet_items_select_public_look on public.closet_items;
drop policy if exists closet_item_images_select_public_look on public.closet_item_images;

create or replace function private.fetch_public_look_garments(p_outfit_ids uuid[])
returns table (
  outfit_id uuid,
  closet_item_id uuid,
  name text,
  brand text,
  category public.clothing_category,
  role public.clothing_category,
  formality_score smallint,
  sort_order integer,
  display_image_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    oi.outfit_id,
    ci.id as closet_item_id,
    coalesce(nullif(btrim(ci.name), ''), nullif(btrim(ci.subcategory), ''), ci.category::text) as name,
    ci.brand,
    ci.category,
    oi.role,
    ci.formality_score,
    oi.sort_order,
    image.display_image_id
  from public.outfit_items oi
  join public.closet_items ci on ci.id = oi.closet_item_id
  left join lateral (
    select img.id as display_image_id
    from public.closet_item_images img
    where img.closet_item_id = ci.id
    order by img.is_primary desc, img.created_at asc
    limit 1
  ) image on true
  where (select auth.uid()) is not null
    and oi.outfit_id = any(coalesce(p_outfit_ids, array[]::uuid[]))
    and oi.closet_item_id is not null
    and private.is_public_worn_outfit(oi.outfit_id)
  order by oi.outfit_id, oi.sort_order, oi.id;
$$;

revoke all on function private.fetch_public_look_garments(uuid[]) from public, anon, authenticated;
grant execute on function private.fetch_public_look_garments(uuid[]) to authenticated;

comment on function private.fetch_public_look_garments(uuid[]) is
  'Returns only display-safe garment fields for active public worn looks. Purchase, fit, size, laundry, wear history, image-analysis metadata, and owner ids are intentionally excluded.';

-- PostgREST exposes public, so this wrapper is SECURITY INVOKER. It can call
-- the private, guarded definer function but does not itself elevate privileges.
create or replace function public.fetch_public_look_garments(p_outfit_ids uuid[])
returns table (
  outfit_id uuid,
  closet_item_id uuid,
  name text,
  brand text,
  category public.clothing_category,
  role public.clothing_category,
  formality_score smallint,
  sort_order integer,
  display_image_id uuid
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.fetch_public_look_garments(p_outfit_ids);
$$;

revoke all on function public.fetch_public_look_garments(uuid[]) from public, anon, authenticated;
grant execute on function public.fetch_public_look_garments(uuid[]) to authenticated;

comment on function public.fetch_public_look_garments(uuid[]) is
  'Data API entry point for Discover and public look detail. Its private implementation returns only a sanitized public display payload and opaque display-image ids.';

-- A report is valid only for a public, active, worn look. This prevents using
-- the report table as an existence oracle for private outfit ids.
drop policy if exists lookbook_reports_insert_own on public.lookbook_reports;
create policy lookbook_reports_insert_own on public.lookbook_reports
  for insert to authenticated
  with check (
    reporter_id = (select auth.uid())
    and (select private.is_public_worn_outfit(lookbook_reports.outfit_id))
  );
