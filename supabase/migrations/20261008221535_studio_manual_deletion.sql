-- Individual deletion shares the fenced, Storage-verified cleanup queue.
-- Only the JWT-authenticating Edge Function may call these invoker RPCs.
revoke delete on public.studio_generations from public,anon,authenticated;
drop policy if exists studio_generations_delete_own on public.studio_generations;
create policy studio_files_server_delete on storage.objects as restrictive
  for delete to authenticated using (
    bucket_id <> 'user-content' or (storage.foldername(name))[3] is distinct from 'studio'
  );

create function public.prepare_studio_deletion(p_user_id uuid,p_generation_id uuid)
returns public.studio_retention_jobs language plpgsql security invoker set search_path='' as $$
declare g public.studio_generations; j public.studio_retention_jobs;
begin
  select * into g from public.studio_generations where id=p_generation_id and user_id=p_user_id for update;
  if not found then
    select * into j from public.studio_retention_jobs where generation_key=p_generation_id and user_id=p_user_id;
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
revoke all on function public.prepare_studio_deletion(uuid,uuid) from public,anon,authenticated;
grant execute on function public.prepare_studio_deletion(uuid,uuid) to service_role;

create function public.claim_studio_deletion(p_user_id uuid,p_job_id uuid,p_token uuid)
returns setof public.studio_retention_jobs language sql security invoker set search_path='' as $$
  update public.studio_retention_jobs j set status='processing',claim_token=p_token,
    claim_expires_at=now()+interval '180 seconds',attempts=attempts+1
  where j.id in(select id from public.studio_retention_jobs where id=p_job_id and user_id=p_user_id
    and status<>'complete' and (claim_expires_at is null or claim_expires_at<now()) for update skip locked)
  returning j.*;
$$;
revoke all on function public.claim_studio_deletion(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.claim_studio_deletion(uuid,uuid,uuid) to service_role;

create unique index studio_retention_generation_key_idx on public.studio_retention_jobs(user_id,generation_key);

-- Recheck generated-source dependencies after locking, just like saves.
create or replace function public.prepare_studio_retention(p_limit integer default 25) returns integer
language plpgsql security invoker set search_path='' as $$
declare g public.studio_generations; n integer:=0;
begin
  if not exists(select 1 from public.studio_retention_config where singleton and enabled) then return 0; end if;
  for g in select * from public.studio_generations s
    where s.deleted_at is null and s.status in ('complete','failed') and s.retention_expires_at < now()
      and not exists(select 1 from public.studio_lookbook_entries e where e.generation_id=s.id)
      and not exists(select 1 from public.studio_generations dependent
        where dependent.id<>s.id and dependent.deleted_at is null and s.result_image_path is not null
          and dependent.reference_image_path=s.result_image_path)
    order by s.retention_expires_at,s.id limit least(greatest(p_limit,1),100) for update of s skip locked
  loop
    -- Recheck after row locking to honor a save that committed while selecting.
    if exists(select 1 from public.studio_lookbook_entries where generation_id=g.id) then continue; end if;
    if g.result_image_path is not null and exists(select 1 from public.studio_generations dependent
      where dependent.id<>g.id and dependent.deleted_at is null and dependent.reference_image_path=g.result_image_path) then continue; end if;
    update public.studio_generations set deleted_at=now() where id=g.id;
    insert into public.studio_retention_jobs(user_id,generation_id,generation_key,result_image_path)
      values(g.user_id,g.id,g.id,g.result_image_path) on conflict(generation_id) do nothing;
    n:=n+1;
  end loop;
  return n;
end;
$$;
