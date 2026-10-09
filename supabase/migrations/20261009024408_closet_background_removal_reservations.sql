-- Service-only ledger. Disabled until provider/credential/privacy acceptance.
-- The invoker can verify account type without reading email/password metadata.
grant select(id,is_anonymous) on auth.users to service_role;
create table public.closet_cutout_config (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false,
  daily_limit integer not null default 5 check(daily_limit between 1 and 100),
  monthly_limit integer not null default 20 check(monthly_limit between 1 and 1000)
);
insert into public.closet_cutout_config(singleton) values(true);
create table public.closet_cutout_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_path text not null,
  request_key text not null check(length(request_key) between 1 and 128),
  state text not null default 'reserved' check(state in ('reserved','dispatched','completed','failed')),
  provider_attempted boolean not null default false,
  output_path text,
  created_at timestamptz not null default now(),
  unique(user_id,source_path), unique(user_id,request_key),
  check((state='completed')=(output_path is not null))
);
create index closet_cutout_owner_time on public.closet_cutout_requests(user_id,created_at);
alter table public.closet_cutout_config enable row level security;
alter table public.closet_cutout_requests enable row level security;
revoke all on public.closet_cutout_config,public.closet_cutout_requests from public,anon,authenticated;
grant select,update on public.closet_cutout_config to service_role;
grant select,insert,update on public.closet_cutout_requests to service_role;

create function public.claim_closet_cutout(p_user uuid,p_source text,p_key text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare r public.closet_cutout_requests; c public.closet_cutout_config; d timestamptz; m timestamptz;
begin
  if p_user is null or p_key is null or length(p_key) not between 1 and 128 or p_source is null
    or p_source !~ ('^users/'||p_user::text||'/closet/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$') then
    raise exception 'cutout_invalid_input';
  end if;
  if not exists(select 1 from auth.users where id=p_user and is_anonymous is false) then
    raise exception 'cutout_account_required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('closet-cutout:'||p_user::text,0));
  if exists(select 1 from public.closet_cutout_requests where user_id=p_user and request_key=p_key and source_path<>p_source) then
    raise exception 'cutout_key_conflict';
  end if;
  select * into r from public.closet_cutout_requests where user_id=p_user and source_path=p_source for update;
  if found then
    if r.state='completed' then return jsonb_build_object('state','complete','path',r.output_path); end if;
    -- Ambiguous dispatch or a worker crash must never create another vendor call.
    return jsonb_build_object('state','pending');
  end if;
  select * into strict c from public.closet_cutout_config where singleton;
  if not c.enabled then raise exception 'cutout_disabled'; end if;
  if not exists(select 1 from storage.objects where bucket_id='user-content' and name=p_source) then
    raise exception 'cutout_source_unavailable';
  end if;
  d:=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
  m:=date_trunc('month',now() at time zone 'UTC') at time zone 'UTC';
  if (select count(*) from public.closet_cutout_requests where user_id=p_user and created_at>=d)>=c.daily_limit
    or (select count(*) from public.closet_cutout_requests where user_id=p_user and created_at>=m)>=c.monthly_limit then
    raise exception 'cutout_quota_exhausted';
  end if;
  insert into public.closet_cutout_requests(user_id,source_path,request_key) values(p_user,p_source,p_key) returning * into r;
  return jsonb_build_object('state','reserved','token',r.id);
end;
$$;

create function public.begin_closet_cutout(p_token uuid)
returns void language plpgsql security invoker set search_path='' as $$
declare r public.closet_cutout_requests;
begin
  select * into r from public.closet_cutout_requests where id=p_token for update;
  if not found or r.state<>'reserved' then raise exception 'cutout_dispatch_unavailable'; end if;
  if not exists(select 1 from storage.objects where bucket_id='user-content' and name=r.source_path) then
    raise exception 'cutout_source_unavailable';
  end if;
  update public.closet_cutout_requests set state='dispatched',provider_attempted=true where id=p_token;
end;
$$;

create function public.complete_closet_cutout(p_token uuid,p_path text)
returns void language plpgsql security invoker set search_path='' as $$
declare r public.closet_cutout_requests;
begin
  select * into r from public.closet_cutout_requests where id=p_token for update;
  if not found or r.state<>'dispatched' or p_path is distinct from regexp_replace(r.source_path,'\.jpg$','-cutout.png') then
    raise exception 'cutout_completion_unavailable';
  end if;
  if not exists(select 1 from storage.objects where bucket_id='user-content' and name=r.source_path)
    or not exists(select 1 from storage.objects where bucket_id='user-content' and name=p_path) then
    raise exception 'cutout_source_unavailable';
  end if;
  update public.closet_cutout_requests set state='completed',output_path=p_path where id=p_token;
end;
$$;

create function public.fail_closet_cutout(p_token uuid,p_attempted boolean)
returns void language plpgsql security invoker set search_path='' as $$
begin
  update public.closet_cutout_requests set state='failed',provider_attempted=provider_attempted or coalesce(p_attempted,true)
    where id=p_token and state<>'completed';
end;
$$;
revoke all on function public.claim_closet_cutout(uuid,text,text),public.begin_closet_cutout(uuid),
  public.complete_closet_cutout(uuid,text),public.fail_closet_cutout(uuid,boolean) from public,anon,authenticated;
grant execute on function public.claim_closet_cutout(uuid,text,text),public.begin_closet_cutout(uuid),
  public.complete_closet_cutout(uuid,text),public.fail_closet_cutout(uuid,boolean) to service_role;
