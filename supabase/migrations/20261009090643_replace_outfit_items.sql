-- Atomically edit an existing owner-owned outfit and replace its
-- closet item set without changing outfits.id or historical outfit_wears.
create or replace function public.replace_outfit_items(
  p_outfit_id uuid,
  p_expected_updated_at timestamptz,
  p_name text,
  p_description text,
  p_compatibility_score smallint,
  p_items jsonb
)
returns public.outfits
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_owner uuid := auth.uid();
  v_outfit public.outfits%rowtype;
  v_item_count integer;
  v_valid_item_count integer;
begin
  if v_owner is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if p_name is null or length(btrim(p_name)) < 1 or length(btrim(p_name)) > 120 then
    raise exception using errcode = '22023', message = 'Outfit name must contain between 1 and 120 characters.';
  end if;
  if p_items is null or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'items must be an array.';
  end if;
  v_item_count := jsonb_array_length(p_items);
  if v_item_count < 1 or v_item_count > 12 then
    raise exception using errcode = '22023', message = 'Outfit must contain between 1 and 12 owned items.';
  end if;
  if p_compatibility_score is not null and p_compatibility_score not between 0 and 100 then
    raise exception using errcode = '22023', message = 'Compatibility score must be between 0 and 100.';
  end if;

  select * into v_outfit
  from public.outfits
  where id = p_outfit_id and user_id = v_owner and archived_at is null
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Outfit not found.';
  end if;
  if p_expected_updated_at is null or v_outfit.updated_at <> p_expected_updated_at then
    raise exception using errcode = '40001', message = 'Outfit changed since it was opened. Reload before saving.';
  end if;

  -- Parse and validate before mutating. JSON role names must be actual
  -- clothing_category values, IDs must be unique, and every garment must
  -- still belong to this authenticated owner and remain active.
  if exists (
    select 1
    from jsonb_to_recordset(p_items) as item(closet_item_id uuid, role text, sort_order integer)
    where item.closet_item_id is null or item.role is null or item.sort_order is null
       or item.sort_order < 0 or item.sort_order >= v_item_count
  ) then
    raise exception using errcode = '22023', message = 'Each item requires an owned ID, role, and valid order.';
  end if;
  if (select count(distinct (item.sort_order)) from jsonb_to_recordset(p_items) as item(closet_item_id uuid, role text, sort_order integer)) <> v_item_count then
    raise exception using errcode = '22023', message = 'Item order must be unique.';
  end if;
  if (select count(distinct (item.closet_item_id)) from jsonb_to_recordset(p_items) as item(closet_item_id uuid, role text, sort_order integer)) <> v_item_count then
    raise exception using errcode = '22023', message = 'A closet item may appear only once.';
  end if;
  -- Lock the validated rows until the replacement commits so a concurrent
  -- archive/delete cannot invalidate a row between validation and insert.
  perform ci.id
  from public.closet_items ci
  join jsonb_to_recordset(p_items) as item(closet_item_id uuid, role text, sort_order integer)
    on ci.id = item.closet_item_id
  where ci.user_id = v_owner and ci.archived_at is null
    and ci.category::text = item.role
  order by ci.id
  for share of ci;
  get diagnostics v_valid_item_count = row_count;
  if v_valid_item_count <> v_item_count then
    raise exception using errcode = '42501', message = 'Every outfit item must be an active garment in your closet with a matching role.';
  end if;

  update public.outfits
  set name = nullif(btrim(p_name), ''),
      description = p_description,
      compatibility_score = p_compatibility_score
  where id = p_outfit_id and user_id = v_owner
  returning * into v_outfit;

  delete from public.outfit_items
  where outfit_id = p_outfit_id and user_id = v_owner;

  insert into public.outfit_items(outfit_id, user_id, closet_item_id, role, sort_order, is_required)
  select p_outfit_id, v_owner, item.closet_item_id, item.role::public.clothing_category, item.sort_order, true
  from jsonb_to_recordset(p_items) as item(closet_item_id uuid, role text, sort_order integer)
  order by item.sort_order;

  return v_outfit;
end;
$$;

revoke all on function public.replace_outfit_items(uuid, timestamptz, text, text, smallint, jsonb) from public, anon;
grant execute on function public.replace_outfit_items(uuid, timestamptz, text, text, smallint, jsonb) to authenticated;
comment on function public.replace_outfit_items(uuid, timestamptz, text, text, smallint, jsonb) is
  'Optimistic, atomic replacement of an existing owner-owned outfit and its owned closet-item rows. Preserves outfit identity and wear history.';
