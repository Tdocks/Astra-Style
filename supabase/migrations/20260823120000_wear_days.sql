-- ============================================================================
-- wear_days — consecutive calendar days with any mark-worn (ADR 0020)
-- ============================================================================
-- A streak is not closet_items.wear_count. Each distinct UTC calendar day
-- the user recorded an outfit wear or an item last_worn_at stamp is one
-- wear_days row. Home/Profile chrome reads this table; Unlocks does not.
-- ============================================================================

set search_path = public, extensions;

create table if not exists public.wear_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  worn_on date not null,
  primary key (user_id, worn_on)
);

comment on table public.wear_days is
  'One row per user per UTC calendar day they marked anything worn (outfit_wears or closet_items.last_worn_at). Streak chrome, not a badge on wear_count (ADR 0020).';

create index if not exists idx_wear_days_user_worn_on
  on public.wear_days (user_id, worn_on desc);

alter table public.wear_days enable row level security;

drop policy if exists wear_days_select_own on public.wear_days;
create policy wear_days_select_own on public.wear_days
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists wear_days_insert_own on public.wear_days;
create policy wear_days_insert_own on public.wear_days
  for insert to authenticated
  with check (user_id = (select auth.uid()));

-- No update/delete for authenticated: days are facts. Account deletion
-- cascades from auth.users.

create or replace function public.record_wear_day(p_user uuid, p_at timestamptz)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if p_user is null or p_at is null then
    return;
  end if;
  insert into public.wear_days (user_id, worn_on)
  values (p_user, (p_at at time zone 'utc')::date)
  on conflict do nothing;
end;
$$;

create or replace function public.trg_outfit_wears_record_wear_day()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform public.record_wear_day(new.user_id, new.worn_at);
  return new;
end;
$$;

drop trigger if exists trg_outfit_wears_record_wear_day on public.outfit_wears;
create trigger trg_outfit_wears_record_wear_day
  after insert on public.outfit_wears
  for each row
  execute function public.trg_outfit_wears_record_wear_day();

create or replace function public.trg_closet_items_record_wear_day()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.last_worn_at is not null
     and (old.last_worn_at is distinct from new.last_worn_at) then
    perform public.record_wear_day(new.user_id, new.last_worn_at);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_closet_items_record_wear_day on public.closet_items;
create trigger trg_closet_items_record_wear_day
  after update of last_worn_at on public.closet_items
  for each row
  execute function public.trg_closet_items_record_wear_day();

insert into public.wear_days (user_id, worn_on)
select distinct w.user_id, (w.worn_at at time zone 'utc')::date
from public.outfit_wears w
on conflict do nothing;

insert into public.wear_days (user_id, worn_on)
select distinct c.user_id, (c.last_worn_at at time zone 'utc')::date
from public.closet_items c
where c.last_worn_at is not null
on conflict do nothing;
