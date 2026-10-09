-- Durable cleanup for a generated result uploaded after its owner/job became
-- ineligible. This queue deliberately has no auth.users or generations FK:
-- account erasure may remove both rows before Storage cleanup can be retried.
create table public.studio_orphan_result_cleanup_jobs (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null,
  generation_id uuid not null,
  storage_path text not null unique,
  status text not null default 'pending' check (status in ('pending', 'processing')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  claim_token uuid,
  claim_expires_at timestamptz,
  created_at timestamptz not null default now()
);

-- The worker needs the pending/processing deletion fence before it removes a
-- result. Keep the grant server-only; the table's owner-facing read policy is
-- unchanged and service_role still has no direct Auth users read grant.
grant select on public.account_deletions to service_role;

create index studio_orphan_result_cleanup_pending_idx
  on public.studio_orphan_result_cleanup_jobs (available_at, created_at, id)
  where status <> 'complete';

alter table public.studio_orphan_result_cleanup_jobs enable row level security;
revoke all on public.studio_orphan_result_cleanup_jobs from public, anon, authenticated;
grant all on public.studio_orphan_result_cleanup_jobs to service_role;

create function public.enqueue_studio_orphan_result_cleanup(
  p_owner_id uuid,
  p_generation_id uuid,
  p_storage_path text
) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  if p_storage_path <> 'users/' || p_owner_id::text || '/studio/' || p_generation_id::text || '/result.png' then
    raise exception 'studio_orphan_result_path_invalid';
  end if;

  insert into public.studio_orphan_result_cleanup_jobs (
    owner_user_id, generation_id, storage_path
  ) values (p_owner_id, p_generation_id, p_storage_path)
  on conflict (storage_path) do update set
    status = case
      when public.studio_orphan_result_cleanup_jobs.status = 'processing' then 'processing'
      else 'pending'
    end,
    available_at = case
      when public.studio_orphan_result_cleanup_jobs.status = 'processing'
        then public.studio_orphan_result_cleanup_jobs.available_at
      else now()
    end;
end;
$$;
revoke all on function public.enqueue_studio_orphan_result_cleanup(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.enqueue_studio_orphan_result_cleanup(uuid, uuid, text)
  to service_role;

-- Safe to remove only when account erasure is pending, or the exact owner/job
-- is no longer a live render. Auth deletion cascades the generation row, so
-- this worker does not need (or have permission) to read auth.users.
create function public.studio_orphan_result_disposition(
  p_owner_id uuid,
  p_generation_id uuid
) returns text
language sql security invoker set search_path = '' as $$
  select case
    when exists (
      select 1 from public.account_deletions d
      where d.user_id = p_owner_id and d.status in ('pending', 'processing')
    ) then 'remove'
    when not exists (
      select 1 from public.studio_generations g
      where g.id = p_generation_id and g.user_id = p_owner_id
    ) then 'remove'
    when exists (
      select 1 from public.studio_generations g
      where g.id = p_generation_id and g.user_id = p_owner_id and g.deleted_at is not null
    ) then 'remove'
    when exists (
      select 1 from public.studio_generations g
      where g.id = p_generation_id and g.user_id = p_owner_id
        and g.deleted_at is null and g.status = 'complete'
        and g.result_image_path = 'users/' || p_owner_id::text || '/studio/' || p_generation_id::text || '/result.png'
    ) then 'preserve'
    when exists (
      select 1 from public.studio_generations g
      where g.id = p_generation_id and g.user_id = p_owner_id
        and g.deleted_at is null and g.status in ('queued', 'generating')
    ) then 'defer'
    else 'remove'
  end;
$$;
revoke all on function public.studio_orphan_result_disposition(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.studio_orphan_result_disposition(uuid, uuid)
  to service_role;

create function public.claim_studio_orphan_result_cleanup(
  p_token uuid,
  p_limit integer default 25
) returns setof public.studio_orphan_result_cleanup_jobs
language sql security invoker set search_path = '' as $$
  update public.studio_orphan_result_cleanup_jobs j
  set status = 'processing', claim_token = p_token,
      claim_expires_at = now() + interval '180 seconds', attempts = attempts + 1
  where j.id in (
    select id from public.studio_orphan_result_cleanup_jobs
    where status <> 'complete' and available_at <= now()
      and (claim_expires_at is null or claim_expires_at < now())
    order by available_at, created_at, id
    limit least(greatest(p_limit, 1), 100)
    for update skip locked
  )
  returning j.*;
$$;
revoke all on function public.claim_studio_orphan_result_cleanup(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.claim_studio_orphan_result_cleanup(uuid, integer)
  to service_role;

create function public.finish_studio_orphan_result_cleanup(
  p_job_id uuid,
  p_token uuid,
  p_succeeded boolean
) returns boolean
language plpgsql security invoker set search_path = '' as $$
declare j public.studio_orphan_result_cleanup_jobs;
begin
  select * into j from public.studio_orphan_result_cleanup_jobs
    where id = p_job_id and claim_token = p_token and status = 'processing'
    for update;
  if not found then return false; end if;

  if p_succeeded then
    if exists (
      select 1 from storage.objects
      where bucket_id = 'user-content' and name = j.storage_path
    ) and not exists (
      select 1 from public.studio_generations g
      where g.id = j.generation_id and g.user_id = j.owner_user_id
        and g.deleted_at is null and g.status = 'complete'
        and g.result_image_path = j.storage_path
    ) then
      raise exception 'studio_orphan_result_object_not_removed';
    end if;
    delete from public.studio_orphan_result_cleanup_jobs where id = j.id;
  else
    update public.studio_orphan_result_cleanup_jobs
      set status = 'pending', available_at = now() + interval '5 minutes',
          claim_token = null, claim_expires_at = null
      where id = j.id;
  end if;
  return true;
end;
$$;
revoke all on function public.finish_studio_orphan_result_cleanup(uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.finish_studio_orphan_result_cleanup(uuid, uuid, boolean)
  to service_role;

create function public.complete_studio_orphan_result_cleanup(p_storage_path text)
returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  delete from public.studio_orphan_result_cleanup_jobs
    where storage_path = p_storage_path and status = 'pending'
      and not exists (
        select 1 from storage.objects
        where bucket_id = 'user-content' and name = p_storage_path
      );
  return found;
end;
$$;
revoke all on function public.complete_studio_orphan_result_cleanup(text)
  from public, anon, authenticated;
grant execute on function public.complete_studio_orphan_result_cleanup(text)
  to service_role;
