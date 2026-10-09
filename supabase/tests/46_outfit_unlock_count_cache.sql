-- Database security, closet invalidation, bounded retention, and account cleanup.
begin;
create temporary table unlock_cache_fixture(owner_id uuid, peer_id uuid, item_id uuid, version bigint);
insert into unlock_cache_fixture values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),null);
do $$
declare
  f record;
  initial_version bigint;
  after_insert bigint;
  current_version bigint;
begin
  select * into f from unlock_cache_fixture;
  insert into auth.users(id,email) values
    (f.owner_id, f.owner_id || '@unlock-cache.invalid'),
    (f.peer_id, f.peer_id || '@unlock-cache.invalid');
  select closet_state_version into initial_version from public.profiles where id = f.owner_id;
  insert into public.closet_items(id,user_id,category,primary_color)
    values(f.item_id,f.owner_id,'top','navy');
  select closet_state_version into after_insert from public.profiles where id = f.owner_id;
  if after_insert <> initial_version + 1 then
    raise exception 'closet insert did not advance scoring version: % -> %', initial_version, after_insert;
  end if;
  update public.closet_items set laundry_state='laundry', availability_state='lost' where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> after_insert then
    raise exception 'laundry/availability edit must not invalidate hypothetical unlock counts';
  end if;
  update public.closet_items set name='A new display name' where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> after_insert then
    raise exception 'non-scoring metadata unexpectedly changed closet version';
  end if;
  current_version := after_insert;
  update public.closet_items set category='bottom' where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> current_version + 1 then raise exception 'category change did not bump closet version'; end if;
  current_version := current_version + 1;
  update public.closet_items set primary_color='black' where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> current_version + 1 then raise exception 'primary color change did not bump closet version'; end if;
  current_version := current_version + 1;
  update public.closet_items set secondary_colors='["white"]'::jsonb where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> current_version + 1 then raise exception 'secondary color change did not bump closet version'; end if;
  current_version := current_version + 1;
  update public.closet_items set pattern='stripe' where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> current_version + 1 then raise exception 'pattern change did not bump closet version'; end if;
  current_version := current_version + 1;
  update public.closet_items set material='[{"fiber":"linen"}]'::jsonb where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> current_version + 1 then raise exception 'material change did not bump closet version'; end if;
  current_version := current_version + 1;
  update public.closet_items set fit='relaxed' where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> current_version + 1 then raise exception 'fit change did not bump closet version'; end if;
  current_version := current_version + 1;
  update public.closet_items set seasonality='["fall"]'::jsonb where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> current_version + 1 then raise exception 'seasonality change did not bump closet version'; end if;
  current_version := current_version + 1;
  update public.closet_items set formality_score=65 where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> current_version + 1 then raise exception 'formality change did not bump closet version'; end if;
  current_version := current_version + 1;
  update public.closet_items set warmth_score=60 where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> current_version + 1 then raise exception 'warmth change did not bump closet version'; end if;
  current_version := current_version + 1;
  update public.closet_items set water_resistance_score=25 where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> current_version + 1 then raise exception 'water resistance change did not bump closet version'; end if;
  current_version := current_version + 1;
  update public.closet_items set archived_at=now() where id=f.item_id;
  if (select closet_state_version from public.profiles where id=f.owner_id) <> current_version + 1 then
    raise exception 'archive did not advance closet version';
  end if;
  update unlock_cache_fixture set version=current_version;
end;
$$;

insert into public.outfit_unlock_count_cache(user_id,cache_key,closet_state_version,weights_version,result,expires_at)
select owner_id,repeat('a',64),version,1,
  '{"unlockCount":2,"novel":true,"gapsFilled":[],"combinationsScored":8,"degraded":[]}'::jsonb,
  now()+interval '30 days' from unlock_cache_fixture;
insert into public.outfit_unlock_count_cache(user_id,cache_key,closet_state_version,weights_version,result,created_at,expires_at)
select peer_id,repeat('b',64),1,1,
  '{"unlockCount":0,"novel":false,"gapsFilled":[],"combinationsScored":0,"degraded":[]}'::jsonb,
  now()-interval '2 days',now()-interval '1 day' from unlock_cache_fixture;

select set_config('request.jwt.claims',json_build_object('sub',owner_id,'role','authenticated')::text,true)
  from unlock_cache_fixture;
select set_config('unlock_cache.owner_id',owner_id::text,true),
  set_config('unlock_cache.item_id',item_id::text,true) from unlock_cache_fixture;
set local role authenticated;
do $$
declare denied boolean := false;
  owner_id uuid := current_setting('unlock_cache.owner_id')::uuid;
  item_id uuid := current_setting('unlock_cache.item_id')::uuid;
  before_version bigint;
begin
  select closet_state_version into before_version from public.profiles where id=owner_id;
  if before_version is null then raise exception 'authenticated caller could not read own closet version'; end if;
  update public.closet_items set fit='slim' where id=item_id;
  if (select closet_state_version from public.profiles where id=owner_id) <> before_version + 1 then
    raise exception 'authenticated closet write did not advance protected scoring version';
  end if;
  denied := false;
  begin
    update public.profiles set closet_state_version=1 where id=owner_id;
  exception when insufficient_privilege then denied := true;
  end;
  if not denied then raise exception 'authenticated caller can forge closet state version'; end if;
  denied := false;
  begin
    perform count(*) from public.outfit_unlock_count_cache;
  exception when insufficient_privilege then denied := true;
  end;
  if not denied then raise exception 'authenticated role read server-only unlock cache'; end if;
end;
$$;
reset role;

set local role service_role;
do $$
declare removed integer; remaining integer;
begin
  removed := public.purge_expired_outfit_unlock_count_cache(1);
  if removed <> 1 then raise exception 'bounded cache purge did not remove exactly one expired row'; end if;
  select count(*)::integer into remaining from public.outfit_unlock_count_cache;
  if remaining <> 1 then raise exception 'cache purge removed active rows or left expired rows'; end if;
end;
$$;
reset role;

delete from auth.users where id=(select owner_id from unlock_cache_fixture);
do $$
begin
  if exists(select 1 from public.outfit_unlock_count_cache where user_id=(select owner_id from unlock_cache_fixture)) then
    raise exception 'account deletion did not cascade unlock cache rows';
  end if;
end;
$$;
rollback;
