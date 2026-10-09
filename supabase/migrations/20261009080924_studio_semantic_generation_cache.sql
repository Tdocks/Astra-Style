-- Semantic generation reuse is distinct from transport idempotency. The key
-- is computed by the server from owner-scoped resolved render inputs and a
-- versioned prompt/provider identity. Explicit rerolls include a fresh nonce.
alter table public.studio_generations
  add column cache_key text check (cache_key is null or cache_key ~ '^[0-9a-f]{64}$'),
  add column cache_expires_at timestamptz;
create index studio_generations_live_semantic_cache
  on public.studio_generations(user_id,cache_key,cache_expires_at)
  where cache_key is not null and deleted_at is null;

create function public.set_studio_generation_cache_expiry() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if new.status='complete' and old.status<>'complete' and new.cache_key is not null then
    new.cache_expires_at:=now()+interval '90 days';
  elsif new.cache_key is null then
    new.cache_expires_at:=null;
  end if;
  return new;
end;
$$;
revoke all on function public.set_studio_generation_cache_expiry() from public,anon,authenticated;
create trigger studio_generation_cache_expiry before update of status,cache_key on public.studio_generations
for each row execute function public.set_studio_generation_cache_expiry();

-- A cache hit must be owner-scoped, visible, within both retention windows,
-- backed by a still-present Storage object, and either complete or actively
-- being processed. A stale queued row or an expired provider-poll lease is
-- deliberately not reusable.
create function public.find_studio_generation_cache(p_user_id uuid,p_cache_key text)
returns setof public.studio_generations language sql security invoker set search_path='' as $$
  select g.* from public.studio_generations g
  where g.user_id=p_user_id and g.cache_key=p_cache_key and g.deleted_at is null
    and ((g.status='complete' and g.cache_expires_at>now()
          and (g.retention_expires_at is null or g.retention_expires_at>now())
          and g.result_image_path is not null
          and exists(select 1 from storage.objects o where o.bucket_id='user-content' and o.name=g.result_image_path))
      or (g.status='queued' and g.created_at>now()-interval '15 minutes'
          and (g.claim_expires_at is null or g.claim_expires_at>now()))
      or (g.status='generating' and g.claim_token is not null and g.claim_expires_at>now()))
  order by (g.status='complete') desc,g.created_at desc,g.id desc limit 1 for update of g;
$$;
revoke all on function public.find_studio_generation_cache(uuid,text) from public,anon,authenticated;
grant execute on function public.find_studio_generation_cache(uuid,text) to service_role;

-- This wrapper shares the existing per-user Studio transaction lock. It
-- checks request-key replay first, then semantic reuse, and only then calls
-- the existing allowance-reserving enqueue RPC. Thus concurrent equivalent
-- submissions cannot race into separate provider jobs/allowances.
create function public.enqueue_studio_generation_cached(
  p_user_id uuid,p_cache_key text,p_request_key uuid,p_request_hash text,
  p_reference_image_path text,p_outfit_id uuid,p_prompt_payload jsonb,p_provider text
) returns setof public.studio_generations language plpgsql security invoker set search_path='' as $$
declare v_request public.studio_submission_requests; v_generation public.studio_generations;
begin
  if p_cache_key is null or p_cache_key !~ '^[0-9a-f]{64}$' then raise exception 'studio_cache_key_invalid'; end if;
  if (p_request_key is null) <> (p_request_hash is null) or
     (p_request_hash is not null and p_request_hash !~ '^[0-9a-f]{64}$') then
    raise exception 'studio_request_invalid';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('studio:'||p_user_id::text,0));
  if p_request_key is not null then
    select * into v_request from public.studio_submission_requests
      where user_id=p_user_id and request_key=p_request_key;
    if v_request.request_key is not null then
      if v_request.request_hash<>p_request_hash then raise exception 'studio_request_conflict'; end if;
      select * into v_generation from public.studio_generations
        where id=v_request.generation_id and user_id=p_user_id;
      if v_generation.id is null or v_generation.deleted_at is not null then raise exception 'studio_request_removed'; end if;
      return next v_generation; return;
    end if;
  end if;
  select * into v_generation from public.find_studio_generation_cache(p_user_id,p_cache_key) limit 1;
  if v_generation.id is not null then
    if p_request_key is not null then
      insert into public.studio_submission_requests(user_id,request_key,request_hash,generation_id)
        values(p_user_id,p_request_key,p_request_hash,v_generation.id);
    end if;
    return next v_generation; return;
  end if;
  if p_request_key is not null then
    select * into v_generation from public.enqueue_studio_generation_idempotent(
      p_user_id,p_request_key,p_request_hash,p_reference_image_path,p_outfit_id,p_prompt_payload,p_provider,null);
  else
    select * into v_generation from public.enqueue_studio_generation(
      p_user_id,p_reference_image_path,p_outfit_id,p_prompt_payload,p_provider,null);
  end if;
  if v_generation.id is null then raise exception 'studio_request_unavailable'; end if;
  update public.studio_generations set cache_key=p_cache_key
    where id=v_generation.id and user_id=p_user_id returning * into v_generation;
  return next v_generation;
end;
$$;
revoke all on function public.enqueue_studio_generation_cached(uuid,text,uuid,text,text,uuid,jsonb,text)
  from public,anon,authenticated;
grant execute on function public.enqueue_studio_generation_cached(uuid,text,uuid,text,text,uuid,jsonb,text)
  to service_role;
