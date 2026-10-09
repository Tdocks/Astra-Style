-- Scratch database only; run after all migrations and the test-only grants.
-- Proves old null variants remain readable, new variants are exact owner
-- siblings, malformed/cross-owner variants are rejected, and row RLS remains.
begin;
do $$
declare
  owner_id uuid := gen_random_uuid();
  peer_id uuid := gen_random_uuid();
  item_id uuid := gen_random_uuid();
  image_id uuid := gen_random_uuid();
  legacy_image_id uuid := gen_random_uuid();
  source_path text;
  thumb_path text;
  rejected boolean := false;
  guest_path text;
begin
  insert into auth.users(id,email) values
    (owner_id, owner_id::text || '@thumbnail-test.invalid'),
    (peer_id, peer_id::text || '@thumbnail-test.invalid');
  source_path := 'users/' || owner_id::text || '/closet/' || image_id::text || '.jpg';
  thumb_path := 'users/' || owner_id::text || '/closet/' || image_id::text || '.thumb.jpg';

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',json_build_object('sub',owner_id,'role','authenticated')::text,true);
  insert into public.closet_items(id,user_id,name,category)
    values(item_id,owner_id,'Synthetic thumbnail item','top');

  insert into public.closet_item_images(
    id,closet_item_id,image_type,storage_path,thumbnail_storage_path,
    background_removed_path,background_removed_thumbnail_path,is_primary
  ) values(
    image_id,item_id,'front',source_path,thumb_path,
    'users/' || owner_id::text || '/closet/' || image_id::text || '-cutout.png',
    'users/' || owner_id::text || '/closet/' || image_id::text || '-cutout.thumb.png',true
  );
  insert into public.closet_item_images(id,closet_item_id,image_type,storage_path,is_primary)
    values(legacy_image_id,item_id,'back','users/' || owner_id::text || '/closet/' || legacy_image_id::text || '.jpg',false);
  if not exists(select 1 from public.closet_item_images where id=image_id and thumbnail_storage_path=thumb_path) then
    raise exception 'Owner could not persist a valid source/thumbnail pair';
  end if;
  if not exists(select 1 from public.closet_item_images where id=legacy_image_id and thumbnail_storage_path is null) then
    raise exception 'Legacy row without a variant did not remain readable';
  end if;

  rejected := false;
  begin
    insert into public.closet_item_images(id,closet_item_id,image_type,storage_path,thumbnail_storage_path)
      values(gen_random_uuid(),item_id,'other',source_path,'users/' || peer_id::text || '/closet/' || image_id::text || '.thumb.jpg');
  exception when check_violation then rejected := true;
  end;
  if not rejected then raise exception 'Foreign-owner thumbnail path was accepted'; end if;

  rejected := false;
  begin
    insert into public.closet_item_images(id,closet_item_id,image_type,storage_path,thumbnail_storage_path)
      values(
        gen_random_uuid(),item_id,'other',source_path,
        'users/' || owner_id::text || '/closet/' || peer_id::text || '.thumb.jpg'
      );
  exception when check_violation then rejected := true;
  end;
  if not rejected then raise exception 'Same-owner non-sibling thumbnail path was accepted'; end if;

  guest_path := 'guest-local/' || owner_id::text || '/' || peer_id::text || '.jpg';
  insert into public.closet_item_images(id,closet_item_id,image_type,storage_path,thumbnail_storage_path)
    values(
      gen_random_uuid(),item_id,'other',guest_path,
      'guest-local/' || owner_id::text || '/' || peer_id::text || '.thumb.jpg'
    );
  if not exists(select 1 from public.closet_item_images where closet_item_id=item_id and storage_path=guest_path) then
    raise exception 'Owner could not persist guest-local photo metadata';
  end if;

  perform set_config('request.jwt.claims',json_build_object('sub',peer_id,'role','authenticated')::text,true);
  if exists(select 1 from public.closet_item_images where id=image_id or id=legacy_image_id) then
    raise exception 'Peer could read another owner''s image metadata';
  end if;
  rejected := false;
  begin
    insert into public.closet_item_images(id,closet_item_id,image_type,storage_path,thumbnail_storage_path)
      values(
        gen_random_uuid(),item_id,'other',
        'users/' || peer_id::text || '/closet/' || peer_id::text || '.jpg',
        'users/' || peer_id::text || '/closet/' || peer_id::text || '.thumb.jpg'
      );
  exception when insufficient_privilege or check_violation or foreign_key_violation or raise_exception then rejected := true;
  end;
  if not rejected then raise exception 'Peer inserted image metadata on another owner item'; end if;
  perform set_config('role','postgres',true);
  raise notice 'Closet image variant constraints, guest-local metadata, legacy-null behavior and owner RLS passed';
end;
$$;
rollback;
