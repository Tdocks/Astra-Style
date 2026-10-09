-- P7-SUB-04: durable UTC daily outfit-generation quota. The default of five is
-- a provisional implementation setting selected for this rollout; §16 says
-- only "limited" generation and does not specify a numeric allowance.
create table public.outfit_generation_quota_config (
  singleton boolean primary key default true check (singleton),
  free_daily_limit integer not null default 5 check (free_daily_limit between 1 and 100)
);
insert into public.outfit_generation_quota_config(singleton) values (true);
alter table public.outfit_generation_quota_config enable row level security;
revoke all on public.outfit_generation_quota_config from public, anon, authenticated;
grant select, update on public.outfit_generation_quota_config to service_role;

create table public.outfit_generation_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  quota_date date not null,
  successful_count integer not null default 0 check (successful_count >= 0),
  primary key (user_id, quota_date)
);
alter table public.outfit_generation_daily_usage enable row level security;
revoke all on public.outfit_generation_daily_usage from public, anon, authenticated;
grant select, insert, update, delete on public.outfit_generation_daily_usage to service_role;

create table public.outfit_generation_reservations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  request_fingerprint text not null,
  quota_date date not null,
  state text not null default 'reserved' check (state in ('reserved', 'committed', 'released')),
  result_payload jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  finished_at timestamptz,
  foreign key (user_id, quota_date)
    references public.outfit_generation_daily_usage(user_id, quota_date) on delete cascade,
  unique (user_id, request_id),
  check ((state = 'committed') = (result_payload is not null))
);
create index outfit_generation_reservations_active_idx
  on public.outfit_generation_reservations(user_id, quota_date, expires_at)
  where state = 'reserved';
alter table public.outfit_generation_reservations enable row level security;
revoke all on public.outfit_generation_reservations from public, anon, authenticated;
grant select, insert, update, delete on public.outfit_generation_reservations to service_role;

create function public.reserve_outfit_generation(
  p_user_id uuid, p_request_id uuid, p_fingerprint text, p_now timestamptz
) returns table(
  allowed boolean, remaining integer, resets_at timestamptz, limit_count integer,
  reservation_id uuid, replay_payload jsonb, in_flight boolean
) language plpgsql security invoker set search_path = '' as $$
declare
  v_day date := (p_now at time zone 'UTC')::date;
  v_reset timestamptz := ((p_now at time zone 'UTC')::date + 1)::timestamp at time zone 'UTC';
  v_limit integer; v_used integer; v_reserved integer; v_existing public.outfit_generation_reservations%rowtype;
  v_id uuid; v_has_existing boolean;
begin
  if p_user_id is null or p_request_id is null or length(p_fingerprint) <> 64 then
    raise exception 'invalid_quota_identity';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('outfit-generation:' || p_user_id::text || ':' || v_day::text, 0));
  select free_daily_limit into strict v_limit from public.outfit_generation_quota_config where singleton;
  insert into public.outfit_generation_daily_usage(user_id, quota_date)
    values (p_user_id, v_day) on conflict do nothing;
  delete from public.outfit_generation_reservations
    where user_id = p_user_id and created_at < p_now - interval '7 days';
  delete from public.outfit_generation_daily_usage
    where user_id = p_user_id and quota_date < v_day - 90;

  select * into v_existing from public.outfit_generation_reservations
    where user_id = p_user_id and request_id = p_request_id for update;
  v_has_existing := found;
  if v_has_existing then
    if v_existing.request_fingerprint <> p_fingerprint then raise exception 'quota_request_id_reused'; end if;
    if v_existing.state = 'committed' then
      return query select true, 0, v_reset, v_limit, v_existing.id, v_existing.result_payload, false;
      return;
    elsif v_existing.state = 'reserved' and v_existing.expires_at > p_now then
      return query select false, 0, v_reset, v_limit, v_existing.id, null::jsonb, true;
      return;
    end if;
  end if;

  update public.outfit_generation_reservations set state = 'released', finished_at = p_now
    where user_id = p_user_id and quota_date = v_day and state = 'reserved' and expires_at <= p_now;
  select successful_count into strict v_used from public.outfit_generation_daily_usage
    where user_id = p_user_id and quota_date = v_day for update;
  select count(*)::integer into v_reserved from public.outfit_generation_reservations
    where user_id = p_user_id and quota_date = v_day and state = 'reserved' and expires_at > p_now;
  if v_used + v_reserved >= v_limit then
    return query select false, greatest(0, v_limit - v_used - v_reserved), v_reset, v_limit, null::uuid, null::jsonb, false;
    return;
  end if;
  if v_has_existing then
    v_id := v_existing.id;
    update public.outfit_generation_reservations set quota_date = v_day, state = 'reserved',
      expires_at = p_now + interval '5 minutes', finished_at = null, result_payload = null
      where id = v_id;
  else
    insert into public.outfit_generation_reservations(user_id, request_id, request_fingerprint, quota_date, expires_at)
      values (p_user_id, p_request_id, p_fingerprint, v_day, p_now + interval '5 minutes') returning id into v_id;
  end if;
  return query select true, greatest(0, v_limit - v_used - v_reserved - 1), v_reset, v_limit, v_id, null::jsonb, false;
end;
$$;

create function public.finish_outfit_generation(
  p_user_id uuid, p_reservation_id uuid, p_succeeded boolean, p_result_payload jsonb, p_now timestamptz
) returns void language plpgsql security invoker set search_path = '' as $$
declare v_row public.outfit_generation_reservations%rowtype;
begin
  select * into v_row from public.outfit_generation_reservations
    where id = p_reservation_id and user_id = p_user_id for update;
  if not found then raise exception 'quota_reservation_not_found'; end if;
  if v_row.state = 'committed' then return; end if;
  if v_row.state = 'released' then
    if p_succeeded then raise exception 'quota_reservation_expired'; end if;
    return;
  end if;
  if v_row.expires_at <= p_now then raise exception 'quota_reservation_expired'; end if;
  if p_succeeded then
    if p_result_payload is null or jsonb_typeof(p_result_payload) <> 'array' or jsonb_array_length(p_result_payload) = 0 then
      raise exception 'quota_result_invalid';
    end if;
    update public.outfit_generation_daily_usage set successful_count = successful_count + 1
      where user_id = p_user_id and quota_date = v_row.quota_date;
    update public.outfit_generation_reservations set state = 'committed', result_payload = p_result_payload, finished_at = p_now
      where id = p_reservation_id;
  else
    update public.outfit_generation_reservations set state = 'released', finished_at = p_now
      where id = p_reservation_id;
  end if;
end;
$$;
revoke all on function public.reserve_outfit_generation(uuid, uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.finish_outfit_generation(uuid, uuid, boolean, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function public.reserve_outfit_generation(uuid, uuid, text, timestamptz) to service_role;
grant execute on function public.finish_outfit_generation(uuid, uuid, boolean, jsonb, timestamptz) to service_role;

-- Keep the 10-item anonymous trial and 30-item signed-in free limit at the
-- database write boundary. The app performs an earlier UX preflight, but this
-- trigger closes direct Data API and concurrent-insert bypasses. It uses only
-- the server-signed top-level is_anonymous JWT claim, never user metadata.
create index closet_items_user_active_count_idx
  on public.closet_items(user_id) where archived_at is null;

create function public.enforce_closet_item_tier_limit()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  v_owner uuid := auth.uid();
  v_is_anonymous boolean;
  v_is_premium boolean;
  v_limit integer;
  v_count integer;
begin
  -- Only a server-held service-role credential may write on behalf of another
  -- owner. Normal API callers must match auth.uid() before any owner count.
  if current_user = 'service_role' or exists (
    select 1 from pg_catalog.pg_roles r where r.rolname = current_user and r.rolsuper
  ) then return new; end if;
  if v_owner is null or new.user_id is distinct from v_owner then
    raise exception using errcode = '42501', message = 'closet_owner_mismatch';
  end if;
  if tg_op = 'UPDATE' then
    if old.archived_at is null or new.archived_at is not null then return new; end if;
  elsif new.archived_at is not null then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('closet-tier-cap:' || v_owner::text, 0));
  v_is_anonymous := coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
  if v_is_anonymous then
    v_limit := 10;
  else
    select exists (
      select 1 from public.subscriptions s
      where s.user_id = v_owner
        and s.status::text in ('trialing', 'active', 'in_grace_period')
        and (s.expires_at is null or s.expires_at > clock_timestamp())
    ) into v_is_premium;
    if v_is_premium then return new; end if;
    v_limit := 30;
  end if;

  select count(*)::integer into v_count
  from public.closet_items ci
  where ci.user_id = v_owner and ci.archived_at is null;
  if v_count >= v_limit then
    raise exception using
      errcode = 'PT409',
      message = 'closet_item_limit_reached',
      detail = json_build_object('limit', v_limit, 'active_count', v_count)::text;
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_closet_item_tier_limit() from public, anon, authenticated;
create trigger closet_item_tier_limit
before insert or update on public.closet_items
for each row execute function public.enforce_closet_item_tier_limit();

-- Preserve the Studio trial and monthly allowance behavior while using the
-- same entitlement statuses as every Edge Function and the native client.
create or replace function public.enqueue_studio_generation(
  p_user_id uuid, p_reference_image_path text, p_outfit_id uuid,
  p_prompt_payload jsonb, p_provider text, p_retry_of uuid default null
) returns setof public.studio_generations
language plpgsql security invoker set search_path='' as $$
declare
  v_allowance uuid;
  v_original public.studio_generations;
  v_existing public.studio_generations;
  v_new public.studio_generations;
  v_premium boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('studio:' || p_user_id::text,0));
  if p_retry_of is not null then
    select * into v_original from public.studio_generations
      where id=p_retry_of and user_id=p_user_id and deleted_at is null;
    if v_original.id is null or v_original.status <> 'failed'
       or coalesce(v_original.prompt_payload->>'is_retryable_failure','false') <> 'true' then
      raise exception 'studio_retry_unavailable';
    end if;
    select * into v_existing from public.studio_generations where retry_of=p_retry_of and user_id=p_user_id;
    if v_existing.id is not null then return next v_existing; return; end if;
    v_allowance := v_original.allowance_id;
    if not exists (select 1 from public.studio_allowances where id=v_allowance and released_at is null and consumed_at is null) then
      raise exception 'studio_retry_unavailable';
    end if;
  else
    select exists (select 1 from public.subscriptions where user_id=p_user_id
      and status::text in ('trialing','active','in_grace_period')
      and (expires_at is null or expires_at > now())) into v_premium;
    if not v_premium and exists (select 1 from public.studio_allowances where user_id=p_user_id and released_at is null) then
      raise exception 'studio_trial_exhausted';
    end if;
    insert into public.studio_allowances(user_id) values(p_user_id) returning id into v_allowance;
  end if;
  if p_outfit_id is not null and not exists (select 1 from public.outfits where id=p_outfit_id and user_id=p_user_id) then
    raise exception 'studio_outfit_unavailable';
  end if;
  insert into public.studio_generations(user_id,reference_image_path,outfit_id,prompt_payload,status,provider,allowance_id,retry_of)
    values(p_user_id,p_reference_image_path,p_outfit_id,p_prompt_payload,'queued',p_provider,v_allowance,p_retry_of) returning * into v_new;
  update public.studio_allowances set latest_generation_id=v_new.id where id=v_allowance;
  return next v_new;
end;
$$;
revoke all on function public.enqueue_studio_generation(uuid,text,uuid,jsonb,text,uuid) from public,anon,authenticated;
grant execute on function public.enqueue_studio_generation(uuid,text,uuid,jsonb,text,uuid) to service_role;

create or replace function public.enforce_studio_premium_monthly_quota()
returns trigger language plpgsql security invoker set search_path='' as $$
declare v_limit integer; v_month timestamptz;
begin
  perform pg_advisory_xact_lock(hashtextextended('studio:'||new.user_id::text,0));
  if exists (select 1 from public.subscriptions where user_id=new.user_id
    and status::text in ('trialing','active','in_grace_period')
    and (expires_at is null or expires_at>now())) then
    select premium_monthly_limit into strict v_limit from public.studio_quota_config where singleton;
    v_month := date_trunc('month',now() at time zone 'UTC') at time zone 'UTC';
    if (select count(*) from public.studio_allowances where user_id=new.user_id
      and released_at is null and created_at>=v_month
      and created_at<((v_month at time zone 'UTC')+interval '1 month') at time zone 'UTC')>=v_limit then
      raise exception 'studio_monthly_quota_exhausted';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_studio_premium_monthly_quota() from public,anon,authenticated;
grant execute on function public.enforce_studio_premium_monthly_quota() to service_role;

create or replace function public.enqueue_studio_hi_res_export(
  p_user_id uuid,
  p_source_generation_id uuid,
  p_provider text,
  p_consent_acknowledged boolean default false,
  p_consent_terms_version text default null
) returns setof public.studio_generations
language plpgsql security invoker set search_path='' as $$
declare
  v_source public.studio_generations;
  v_existing public.studio_generations;
  v_new public.studio_generations;
  v_payload jsonb;
  v_allowance uuid;
  v_premium boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('studio:'||p_user_id::text,0));
  select * into v_source from public.studio_generations
    where id=p_source_generation_id and user_id=p_user_id for update;
  if not found or v_source.status <> 'complete' or v_source.deleted_at is not null
    or (v_source.retention_expires_at is not null and v_source.retention_expires_at<=clock_timestamp())
    or coalesce(v_source.prompt_payload->>'resolution','draft') <> 'draft'
    or v_source.hi_res_source_id is not null
    or (coalesce(v_source.reference_image_path,'')<>'' and
      (length(v_source.reference_image_path)>512 or v_source.reference_image_path like '%..%'
        or v_source.reference_image_path like '/%'))
    or (coalesce(v_source.reference_image_path,'')<>'' and
      coalesce(v_source.prompt_payload->>'mode','reference') not in ('inspiration','closet_inspiration') and
      left(lower(v_source.reference_image_path),length('users/'||lower(p_user_id::text)||'/references/')) <>
        'users/'||lower(p_user_id::text)||'/references/')
    or (coalesce(v_source.reference_image_path,'')<>'' and
      coalesce(v_source.prompt_payload->>'mode','reference') in ('inspiration','closet_inspiration') and
      not exists(select 1 from public.studio_generations parent
        where parent.user_id=p_user_id and parent.result_image_path=v_source.reference_image_path
          and parent.status='complete' and parent.deleted_at is null
          and (parent.retention_expires_at is null or parent.retention_expires_at>clock_timestamp())))
    or v_source.result_image_path is distinct from
      ('users/'||lower(p_user_id::text)||'/studio/'||lower(p_source_generation_id::text)||'/result.png') then
    raise exception 'studio_export_source_unavailable';
  end if;
  if not exists(select 1 from storage.objects where bucket_id='user-content'
    and name=v_source.result_image_path) then
    raise exception 'studio_export_source_unavailable';
  end if;
  if coalesce(v_source.reference_image_path,'')<>'' and not exists(
    select 1 from storage.objects where bucket_id='user-content' and name=v_source.reference_image_path
  ) then
    raise exception 'studio_export_source_unavailable';
  end if;
  select candidate.* into v_existing from public.studio_generations candidate
    where candidate.hi_res_source_id=p_source_generation_id and candidate.user_id=p_user_id
      and not exists(select 1 from public.studio_generations successor
        where successor.retry_of=candidate.id and successor.user_id=p_user_id)
    order by candidate.created_at desc,candidate.id desc limit 1;
  if found then
    if v_existing.deleted_at is not null then raise exception 'studio_export_already_removed'; end if;
    return next v_existing; return;
  end if;
  if p_provider='mock' then raise exception 'studio_hi_res_provider_unavailable'; end if;
  select exists(select 1 from public.subscriptions where user_id=p_user_id
    and status::text in ('trialing','active','in_grace_period')
    and (expires_at is null or expires_at>clock_timestamp())) into v_premium;
  if not v_premium then raise exception 'studio_hi_res_premium_required'; end if;
  if coalesce(v_source.reference_image_path,'')<>'' and
    coalesce(v_source.prompt_payload->>'mode','reference') not in ('inspiration','closet_inspiration') and
    (p_consent_acknowledged is distinct from true or p_consent_terms_version is distinct from '2026-08-17') then
    raise exception 'studio_export_consent_required';
  end if;
  v_payload := jsonb_set(coalesce(v_source.prompt_payload,'{}'::jsonb),'{resolution}','"hi_res"'::jsonb,true);
  v_payload := jsonb_set(v_payload,'{hi_res_source_generation_id}',to_jsonb(v_source.id::text),true);
  if coalesce(v_source.reference_image_path,'')<>'' and
    coalesce(v_source.prompt_payload->>'mode','reference') not in ('inspiration','closet_inspiration') then
    v_payload := jsonb_set(v_payload,'{hi_res_export_consent}',jsonb_build_object(
      'acknowledged',true,
      'terms_version',p_consent_terms_version,
      'attested_at',clock_timestamp()
    ),true);
  end if;
  insert into public.studio_allowances(user_id) values(p_user_id) returning id into v_allowance;
  insert into public.studio_generations(
    user_id,reference_image_path,outfit_id,prompt_payload,status,provider,allowance_id,hi_res_source_id
  ) values (
    p_user_id,v_source.reference_image_path,v_source.outfit_id,v_payload,'queued',p_provider,v_allowance,v_source.id
  ) returning * into v_new;
  update public.studio_allowances set latest_generation_id=v_new.id where id=v_allowance;
  return next v_new;
end;
$$;
revoke all on function public.enqueue_studio_hi_res_export(uuid,uuid,text,boolean,text) from public,anon,authenticated;
grant execute on function public.enqueue_studio_hi_res_export(uuid,uuid,text,boolean,text) to service_role;
