-- P4-OUTFIT-09: owner-scoped, unchanged-input reuse for hypothetical purchase unlock counts.
alter table public.profiles
  add column if not exists closet_state_version bigint not null default 1
    check (closet_state_version > 0);

comment on column public.profiles.closet_state_version is
  'Monotonic version of active closet attributes used by hypothetical outfit unlock scoring. Laundry and availability changes are intentionally excluded.';

create or replace function public.guard_closet_state_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.closet_state_version is distinct from old.closet_state_version
     and pg_trigger_depth() < 2 then
    raise exception 'closet_state_version_is_managed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_closet_state_version() from public, anon, authenticated;
drop trigger if exists profiles_guard_closet_state_version on public.profiles;
create trigger profiles_guard_closet_state_version
before update of closet_state_version on public.profiles
for each row execute function public.guard_closet_state_version();

create or replace function public.bump_closet_state_version()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  affected_user uuid;
begin
  if tg_op = 'DELETE' then
    affected_user := old.user_id;
  else
    affected_user := new.user_id;
  end if;
  if tg_op = 'UPDATE' and old.user_id is distinct from new.user_id then
    update public.profiles
       set closet_state_version = closet_state_version + 1
     where id = old.user_id;
  end if;
  update public.profiles
     set closet_state_version = closet_state_version + 1
   where id = affected_user;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.bump_closet_state_version() from public, anon, authenticated;

drop trigger if exists closet_items_bump_scoring_version_insert_delete on public.closet_items;
create trigger closet_items_bump_scoring_version_insert_delete
after insert or delete on public.closet_items
for each row execute function public.bump_closet_state_version();

drop trigger if exists closet_items_bump_scoring_version_update on public.closet_items;
create trigger closet_items_bump_scoring_version_update
after update of id, user_id, category, primary_color, secondary_colors, pattern, material, fit,
  seasonality, formality_score, warmth_score, water_resistance_score, archived_at
on public.closet_items
for each row
when (
  old.id is distinct from new.id or
  old.user_id is distinct from new.user_id or
  old.category is distinct from new.category or
  old.primary_color is distinct from new.primary_color or
  old.secondary_colors is distinct from new.secondary_colors or
  old.pattern is distinct from new.pattern or
  old.material is distinct from new.material or
  old.fit is distinct from new.fit or
  old.seasonality is distinct from new.seasonality or
  old.formality_score is distinct from new.formality_score or
  old.warmth_score is distinct from new.warmth_score or
  old.water_resistance_score is distinct from new.water_resistance_score or
  old.archived_at is distinct from new.archived_at
)
execute function public.bump_closet_state_version();

create table public.outfit_unlock_count_cache (
  user_id uuid not null references auth.users(id) on delete cascade,
  cache_key text not null check (cache_key ~ '^[0-9a-f]{64}$'),
  closet_state_version bigint not null check (closet_state_version > 0),
  weights_version integer not null check (weights_version > 0),
  result jsonb not null check (
    jsonb_typeof(result) = 'object' and
    jsonb_typeof(result->'unlockCount') = 'number' and
    jsonb_typeof(result->'novel') = 'boolean' and
    jsonb_typeof(result->'gapsFilled') = 'array' and
    jsonb_typeof(result->'combinationsScored') = 'number' and
    jsonb_typeof(result->'degraded') = 'array'
  ),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (user_id, cache_key),
  check (expires_at > created_at)
);

create index outfit_unlock_count_cache_expiry_idx
  on public.outfit_unlock_count_cache (expires_at);

alter table public.outfit_unlock_count_cache enable row level security;
revoke all on public.outfit_unlock_count_cache from public, anon, authenticated;
grant select, insert, update, delete on public.outfit_unlock_count_cache to service_role;

create or replace function public.purge_expired_outfit_unlock_count_cache(p_limit integer default 100)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  removed integer;
begin
  with doomed as (
    select user_id, cache_key
      from public.outfit_unlock_count_cache
     where expires_at <= now()
     order by expires_at, user_id, cache_key
     limit greatest(1, least(coalesce(p_limit, 100), 500))
     for update skip locked
  ), deleted as (
    delete from public.outfit_unlock_count_cache cache
     using doomed
     where cache.user_id = doomed.user_id and cache.cache_key = doomed.cache_key
     returning 1
  )
  select count(*)::integer into removed from deleted;
  return removed;
end;
$$;

revoke all on function public.purge_expired_outfit_unlock_count_cache(integer) from public, anon, authenticated;
grant execute on function public.purge_expired_outfit_unlock_count_cache(integer) to service_role;
