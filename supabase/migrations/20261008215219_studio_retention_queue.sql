-- Expiration uses Storage API removal, never DELETE storage.objects (ADR 0024).
create table public.studio_retention_config (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false,
  scheduler_token_hash text
);
insert into public.studio_retention_config(singleton) values(true);
alter table public.studio_retention_config enable row level security;
revoke all on public.studio_retention_config from public,anon,authenticated;
grant all on public.studio_retention_config to service_role;

create table public.studio_retention_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  generation_id uuid unique references public.studio_generations(id) on delete set null,
  generation_key uuid not null,
  result_image_path text,
  status text not null default 'pending' check(status in ('pending','processing','complete')),
  attempts integer not null default 0,
  error_message text,
  claim_token uuid,
  claim_expires_at timestamptz,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create index studio_retention_pending_idx on public.studio_retention_jobs(created_at) where status <> 'complete';
create index studio_retention_user_idx on public.studio_retention_jobs(user_id);
create index studio_retention_expiry_idx on public.studio_generations(retention_expires_at)
  where deleted_at is null and status in ('complete','failed');
create index studio_generation_reference_path_idx on public.studio_generations(reference_image_path) where deleted_at is null;
alter table public.studio_retention_jobs enable row level security;
revoke all on public.studio_retention_jobs from public,anon,authenticated;
grant all on public.studio_retention_jobs to service_role;
grant delete on public.studio_generations to service_role;
grant select on storage.objects to service_role;
grant select(id,user_id,generation_id,status,attempts,error_message,created_at,completed_at)
  on public.studio_retention_jobs to authenticated;
create policy studio_retention_jobs_read_own on public.studio_retention_jobs for select to authenticated
  using(user_id=(select auth.uid()));

-- Serialize save with expiration. RLS alone could observe an older row before
-- waiting for a deletion lock. This trigger checks the locked, current row.
create function public.guard_studio_saved_generation() returns trigger
language plpgsql security definer set search_path='' as $$
declare g public.studio_generations;
begin
  if current_setting('role',true)='authenticated' and new.user_id<>(select auth.uid()) then
    raise insufficient_privilege using message='studio_save_unavailable';
  end if;
  select * into g from public.studio_generations where id=new.generation_id and user_id=new.user_id for update;
  if not found or g.status <> 'complete' or g.deleted_at is not null or g.result_image_path is null then
    raise exception 'studio_save_unavailable';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_studio_saved_generation() from public,anon,authenticated;
create trigger studio_saved_generation_guard before insert on public.studio_lookbook_entries
  for each row execute function public.guard_studio_saved_generation();

-- Rerolls must also lock their generated source before expiry can hide it.
create function public.guard_studio_generation_source() returns trigger
language plpgsql security invoker set search_path='' as $$
declare g public.studio_generations;
begin
  if new.reference_image_path like 'users/%/studio/%' then
    select * into g from public.studio_generations where user_id=new.user_id
      and result_image_path=new.reference_image_path for update;
    if not found or g.deleted_at is not null or g.status<>'complete' then
      raise exception 'studio_source_unavailable';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_studio_generation_source() from public,anon,authenticated;
create trigger studio_generation_source_guard before insert or update of reference_image_path
  on public.studio_generations for each row execute function public.guard_studio_generation_source();

create function public.authorize_studio_retention(p_token text) returns boolean
language sql security invoker set search_path='' as $$
  select coalesce((select enabled and scheduler_token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
    from public.studio_retention_config where singleton),false);
$$;
revoke all on function public.authorize_studio_retention(text) from public,anon,authenticated;
grant execute on function public.authorize_studio_retention(text) to service_role;

create function public.prepare_studio_retention(p_limit integer default 25) returns integer
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
    update public.studio_generations set deleted_at=now() where id=g.id;
    insert into public.studio_retention_jobs(user_id,generation_id,generation_key,result_image_path)
      values(g.user_id,g.id,g.id,g.result_image_path) on conflict(generation_id) do nothing;
    n:=n+1;
  end loop;
  return n;
end;
$$;
revoke all on function public.prepare_studio_retention(integer) from public,anon,authenticated;
grant execute on function public.prepare_studio_retention(integer) to service_role;

create function public.claim_studio_retention(p_token uuid,p_limit integer default 25)
returns setof public.studio_retention_jobs language sql security invoker set search_path='' as $$
  update public.studio_retention_jobs j set status='processing',claim_token=p_token,
    claim_expires_at=now()+interval '180 seconds',attempts=attempts+1
  where j.id in(select id from public.studio_retention_jobs where status<>'complete'
    and (claim_expires_at is null or claim_expires_at<now()) order by created_at,id
    limit least(greatest(p_limit,1),100) for update skip locked) returning j.*;
$$;
revoke all on function public.claim_studio_retention(uuid,integer) from public,anon,authenticated;
grant execute on function public.claim_studio_retention(uuid,integer) to service_role;

create function public.finish_studio_retention(p_job_id uuid,p_token uuid,p_succeeded boolean) returns boolean
language plpgsql security invoker set search_path='' as $$
declare j public.studio_retention_jobs;
begin
  select * into j from public.studio_retention_jobs where id=p_job_id and claim_token=p_token and status='processing' for update;
  if not found then return false; end if;
  if p_succeeded then
    if j.result_image_path is not null and exists(select 1 from storage.objects where bucket_id='user-content' and name=j.result_image_path) then
      raise exception 'studio_retention_object_not_removed';
    end if;
    delete from public.studio_generations where id=j.generation_id and user_id=j.user_id and deleted_at is not null;
    update public.studio_retention_jobs set status='complete',result_image_path=null,error_message=null,
      claim_token=null,claim_expires_at=null,completed_at=now() where id=j.id;
  else
    update public.studio_retention_jobs set status='pending',error_message='Image cleanup will be retried.',
      claim_token=null,claim_expires_at=now()+interval '5 minutes' where id=j.id;
  end if;
  return true;
end;
$$;
revoke all on function public.finish_studio_retention(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.finish_studio_retention(uuid,uuid,boolean) to service_role;
