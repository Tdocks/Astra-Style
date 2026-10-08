-- Reference erasure shares the durable Storage API cleanup queue, but has a
-- distinct key namespace. Never delete Storage metadata directly in production.
alter table public.studio_retention_jobs add column kind text not null default 'studio'
  check (kind in ('studio','reference'));
drop index public.studio_retention_generation_key_idx;
create unique index studio_retention_generation_key_idx
  on public.studio_retention_jobs(user_id,kind,generation_key);
grant select(kind) on public.studio_retention_jobs to authenticated;
alter table public.studio_retention_config add column abandoned_reference_hours integer not null default 24
  check(abandoned_reference_hours between 1 and 720);
alter table public.studio_retention_config add column reference_cleanup_enabled boolean not null default false;
grant select,update on public.body_profiles to service_role;
grant select on public.profiles to service_role;

create function public.reference_photo_key(p_user_id uuid,p_path text) returns uuid
language plpgsql immutable security invoker set search_path='' as $$
declare filename text;
begin
  if p_path is null or p_path !~ ('^users/'||p_user_id::text||'/references/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$') then
    raise exception 'reference_photo_unavailable';
  end if;
  filename:=split_part(p_path,'/',4);
  return left(filename,length(filename)-4)::uuid;
end;
$$;
revoke all on function public.reference_photo_key(uuid,text) from public,anon,authenticated;
grant execute on function public.reference_photo_key(uuid,text) to service_role;

-- A retained queue key is a tombstone even after Storage removal completes.
-- This serializes source acceptance with both explicit and abandoned cleanup.
create or replace function public.guard_studio_generation_source() returns trigger
language plpgsql security invoker set search_path='' as $$
declare g public.studio_generations; k uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('studio:'||new.user_id::text,0));
  if new.reference_image_path like 'users/%/references/%' then
    k:=public.reference_photo_key(new.user_id,new.reference_image_path);
    perform pg_advisory_xact_lock(hashtextextended('reference:'||new.reference_image_path,0));
    if exists(select 1 from public.studio_retention_jobs where user_id=new.user_id and kind='reference' and generation_key=k) then
      raise exception 'studio_source_unavailable';
    end if;
  elsif new.reference_image_path like 'users/%/studio/%' then
    select * into g from public.studio_generations where user_id=new.user_id
      and result_image_path=new.reference_image_path for update;
    if not found or g.deleted_at is not null or g.status<>'complete' then
      raise exception 'studio_source_unavailable';
    end if;
  end if;
  return new;
end;
$$;

-- Caller-owned body writes cannot read privileged cleanup path snapshots. The
-- trigger has that narrow privilege; it validates ownership and is not callable.
create function public.guard_body_reference_photos() returns trigger
language plpgsql security definer set search_path='' as $$
declare p text; k uuid;
begin
  if current_setting('role',true)='authenticated' and new.user_id<>(select auth.uid()) then
    raise insufficient_privilege using message='reference_photo_unavailable';
  end if;
  if jsonb_typeof(new.appearance->'reference_selfie_paths') not in ('array') then
    if new.appearance ? 'reference_selfie_paths' then raise exception 'reference_photo_unavailable'; end if;
    return new;
  end if;
  for p in select value from jsonb_array_elements_text(coalesce(new.appearance->'reference_selfie_paths','[]'::jsonb)) order by value loop
    k:=public.reference_photo_key(new.user_id,p);
    perform pg_advisory_xact_lock(hashtextextended('reference:'||p,0));
    if exists(select 1 from public.studio_retention_jobs where user_id=new.user_id and kind='reference' and generation_key=k) then
      raise exception 'reference_photo_unavailable';
    end if;
  end loop;
  return new;
end;
$$;
revoke all on function public.guard_body_reference_photos() from public,anon,authenticated;
create trigger body_reference_photo_guard before insert or update of appearance on public.body_profiles
  for each row execute function public.guard_body_reference_photos();

create policy reference_files_server_delete on storage.objects as restrictive for delete to authenticated
  using(bucket_id<>'user-content' or (storage.foldername(name))[3]<>'references');

create function public.prepare_reference_deletion(p_user_id uuid,p_path text)
returns public.studio_retention_jobs language plpgsql security invoker set search_path='' as $$
declare b public.body_profiles; k uuid; ids uuid[]; g public.studio_generations; j public.studio_retention_jobs;
begin
  k:=public.reference_photo_key(p_user_id,p_path);
  -- Body writers already hold their row before the path guard. Preserve that
  -- ordering, then the same user lock taken by Studio enqueue, then path/rows.
  select * into b from public.body_profiles where user_id=p_user_id for update;
  perform pg_advisory_xact_lock(hashtextextended('studio:'||p_user_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('reference:'||p_path,0));
  select * into j from public.studio_retention_jobs where user_id=p_user_id and kind='reference' and generation_key=k;
  if found then return j; end if;
  if b.user_id is null or not coalesce(b.appearance->'reference_selfie_paths','[]'::jsonb) @> jsonb_build_array(p_path) then
    raise exception 'reference_photo_unavailable';
  end if;
  perform id from public.studio_generations where user_id=p_user_id and deleted_at is null order by id for update;
  with recursive descendants as (
    select id,result_image_path from public.studio_generations where user_id=p_user_id and deleted_at is null and reference_image_path=p_path
    union
    select child.id,child.result_image_path from public.studio_generations child join descendants parent
      on child.reference_image_path=parent.result_image_path
      where child.user_id=p_user_id and child.deleted_at is null
  ) select coalesce(array_agg(id),'{}'::uuid[]) into ids from descendants;
  if exists(select 1 from public.studio_generations where id=any(ids) and status in ('queued','generating')) then
    raise exception 'reference_photo_in_progress';
  end if;
  for g in select * from public.studio_generations where id=any(ids) order by id loop
    update public.studio_generations set deleted_at=now() where id=g.id;
    insert into public.studio_retention_jobs(user_id,generation_id,generation_key,result_image_path)
      values(p_user_id,g.id,g.id,g.result_image_path) on conflict(generation_id) do nothing;
  end loop;
  -- Change only this array in the locked current profile; never restore an old
  -- whole-profile snapshot after a Storage failure.
  update public.body_profiles set appearance=jsonb_set(coalesce(appearance,'{}'::jsonb),'{reference_selfie_paths}',
    coalesce((select jsonb_agg(value) from jsonb_array_elements(coalesce(appearance->'reference_selfie_paths','[]'::jsonb))
      where value<>to_jsonb(p_path)),'[]'::jsonb)) where user_id=p_user_id;
  insert into public.studio_retention_jobs(user_id,generation_key,result_image_path,kind)
    values(p_user_id,k,p_path,'reference') returning * into j;
  return j;
end;
$$;
revoke all on function public.prepare_reference_deletion(uuid,text) from public,anon,authenticated;
grant execute on function public.prepare_reference_deletion(uuid,text) to service_role;

create function public.prepare_reference_retention(p_limit integer default 25) returns integer
language plpgsql security invoker set search_path='' as $$
declare o record; u uuid; k uuid; hours integer; n integer:=0;
begin
  select abandoned_reference_hours into hours from public.studio_retention_config where singleton and enabled and reference_cleanup_enabled;
  if hours is null then return 0; end if;
  for o in select name from storage.objects obj where bucket_id='user-content'
    and name ~ '^users/[0-9a-f-]{36}/references/[0-9a-f-]{36}\.jpg$'
    and greatest(created_at,updated_at)<now()-make_interval(hours=>hours)
    and exists(select 1 from public.profiles a where a.id::text=split_part(obj.name,'/',2))
    and not exists(select 1 from public.body_profiles b where b.user_id::text=split_part(obj.name,'/',2)
      and coalesce(b.appearance->'reference_selfie_paths','[]'::jsonb) @> jsonb_build_array(obj.name))
    and not exists(select 1 from public.studio_generations g where g.user_id::text=split_part(obj.name,'/',2)
      and g.reference_image_path=obj.name and g.deleted_at is null)
    and not exists(select 1 from public.studio_retention_jobs j where j.user_id::text=split_part(obj.name,'/',2)
      and j.kind='reference' and j.status<>'complete' and j.result_image_path=obj.name)
    order by created_at,name limit least(greatest(p_limit,1),100) loop
    begin u:=split_part(o.name,'/',2)::uuid; k:=public.reference_photo_key(u,o.name);
    exception when invalid_text_representation or raise_exception then continue; end;
    if not exists(select 1 from public.profiles where id=u) then continue; end if;
    perform pg_advisory_xact_lock(hashtextextended('studio:'||u::text,0));
    perform pg_advisory_xact_lock(hashtextextended('reference:'||o.name,0));
    if exists(select 1 from public.body_profiles where user_id=u and coalesce(appearance->'reference_selfie_paths','[]'::jsonb) @> jsonb_build_array(o.name))
      or exists(select 1 from public.studio_generations where user_id=u and reference_image_path=o.name and deleted_at is null) then continue; end if;
    -- Recheck object age after waiting, including a replacement upload. Storage
    -- removal itself still goes through the worker's API and finish fence.
    if not exists(select 1 from storage.objects where bucket_id='user-content' and name=o.name
      and greatest(created_at,updated_at)<now()-make_interval(hours=>hours)) then continue; end if;
    insert into public.studio_retention_jobs(user_id,generation_key,result_image_path,kind)
      values(u,k,o.name,'reference') on conflict(user_id,kind,generation_key) do update
      set status='pending',result_image_path=excluded.result_image_path,completed_at=null,
        claim_token=null,claim_expires_at=null where public.studio_retention_jobs.status='complete';
    if found then n:=n+1; end if;
  end loop;
  return n;
end;
$$;
revoke all on function public.prepare_reference_retention(integer) from public,anon,authenticated;
grant execute on function public.prepare_reference_retention(integer) to service_role;

create or replace function public.prepare_studio_deletion(p_user_id uuid,p_generation_id uuid)
returns public.studio_retention_jobs language plpgsql security invoker set search_path='' as $$
declare g public.studio_generations; j public.studio_retention_jobs;
begin
  select * into g from public.studio_generations where id=p_generation_id and user_id=p_user_id for update;
  if not found then
    select * into j from public.studio_retention_jobs where generation_key=p_generation_id and user_id=p_user_id and kind='studio';
    if not found then raise exception 'studio_delete_unavailable'; end if;
    return j;
  end if;
  if g.deleted_at is not null then
    select * into j from public.studio_retention_jobs where generation_id=g.id and user_id=p_user_id;
    if not found then raise exception 'studio_delete_unavailable'; end if;
    return j;
  end if;
  if g.status not in ('complete','failed') then raise exception 'studio_delete_in_progress'; end if;
  -- Source insertion locks this same row. Recheck after acquiring its lock;
  -- neither a concurrent reroll nor a collection save can slip past deletion.
  if g.result_image_path is not null and exists(select 1 from public.studio_generations d
    where d.id<>g.id and d.deleted_at is null and d.reference_image_path=g.result_image_path) then
    raise exception 'studio_delete_has_variations';
  end if;
  update public.studio_generations set deleted_at=now() where id=g.id;
  insert into public.studio_retention_jobs(user_id,generation_id,generation_key,result_image_path)
    values(g.user_id,g.id,g.id,g.result_image_path) returning * into j;
  return j;
end;
$$;
