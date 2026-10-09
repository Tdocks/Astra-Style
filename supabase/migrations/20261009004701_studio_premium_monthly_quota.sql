-- Premium reservations and completed renders share a calendar-month budget.
-- Retrying reuses an allowance; releasing a failed reservation restores capacity.
create table public.studio_quota_config (
  singleton boolean primary key default true check (singleton),
  premium_monthly_limit integer not null default 20 check (premium_monthly_limit between 1 and 1000)
);
insert into public.studio_quota_config(singleton) values(true);
alter table public.studio_quota_config enable row level security;
revoke all on public.studio_quota_config from public,anon,authenticated;
grant select,update on public.studio_quota_config to service_role;

create function public.enforce_studio_premium_monthly_quota()
returns trigger language plpgsql security invoker set search_path='' as $$
declare v_limit integer; v_month timestamptz;
begin
  perform pg_advisory_xact_lock(hashtextextended('studio:'||new.user_id::text,0));
  if exists (select 1 from public.subscriptions where user_id=new.user_id
    and status in ('trialing','active','in_grace_period','in_billing_retry')
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
create trigger studio_premium_monthly_quota before insert on public.studio_allowances
for each row execute function public.enforce_studio_premium_monthly_quota();
