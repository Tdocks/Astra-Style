-- Durable initial-submission deduplication. Server-only records retain the job
-- identity even after a soft deletion, so a replay cannot spend another credit.
create table public.studio_submission_requests (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_key uuid not null,
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  generation_id uuid not null,
  created_at timestamptz not null default now(),
  primary key(user_id,request_key),
  foreign key(generation_id,user_id) references public.studio_generations(id,user_id) on delete cascade
);
alter table public.studio_submission_requests enable row level security;
revoke all on public.studio_submission_requests from public,anon,authenticated;
grant select,insert,delete on public.studio_submission_requests to service_role;

create function public.enqueue_studio_generation_idempotent(
  p_user_id uuid, p_request_key uuid, p_request_hash text,
  p_reference_image_path text, p_outfit_id uuid,
  p_prompt_payload jsonb, p_provider text, p_retry_of uuid default null
) returns setof public.studio_generations
language plpgsql security invoker set search_path='' as $$
declare
  v_request public.studio_submission_requests;
  v_generation public.studio_generations;
begin
  if p_request_key is null or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'studio_request_invalid';
  end if;
  -- Same user lock as the existing allowance transaction: callers cannot race
  -- a duplicate submission against either an initial request or explicit retry.
  perform pg_advisory_xact_lock(hashtextextended('studio:'||p_user_id::text,0));
  select * into v_request from public.studio_submission_requests
    where user_id=p_user_id and request_key=p_request_key;
  if v_request.request_key is not null then
    if v_request.request_hash <> p_request_hash then raise exception 'studio_request_conflict'; end if;
    select * into v_generation from public.studio_generations
      where id=v_request.generation_id and user_id=p_user_id;
    if v_generation.id is null or v_generation.deleted_at is not null then
      raise exception 'studio_request_removed';
    end if;
    return next v_generation; return;
  end if;
  select * into v_generation from public.enqueue_studio_generation(
    p_user_id,p_reference_image_path,p_outfit_id,p_prompt_payload,p_provider,p_retry_of);
  if v_generation.id is null then raise exception 'studio_request_unavailable'; end if;
  insert into public.studio_submission_requests(user_id,request_key,request_hash,generation_id)
    values(p_user_id,p_request_key,p_request_hash,v_generation.id);
  return next v_generation;
end;
$$;
revoke all on function public.enqueue_studio_generation_idempotent(uuid,uuid,text,text,uuid,jsonb,text,uuid)
  from public,anon,authenticated;
grant execute on function public.enqueue_studio_generation_idempotent(uuid,uuid,text,text,uuid,jsonb,text,uuid)
  to service_role;
