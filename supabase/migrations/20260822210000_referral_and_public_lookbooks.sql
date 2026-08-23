-- ============================================================================
-- Growth leftovers: referral codes, public worn lookbooks, report stub.
-- ============================================================================
-- ADR 0017: Discover may list other men's public worn looks. Home stays
-- private. Visibility defaults to private so existing RLS isolation on
-- outfits still holds for every row that has not opted in.
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- outfit_visibility
-- ----------------------------------------------------------------------------
do $$
begin
  create type outfit_visibility as enum ('private', 'public');
exception
  when duplicate_object then null;
end
$$;

alter table public.outfits
  add column if not exists visibility public.outfit_visibility not null default 'private';

comment on column public.outfits.visibility is
  'private until the owner opts in after a wear. Discover may list public worn looks; Home never does.';

create index if not exists outfits_public_worn_idx
  on public.outfits (updated_at desc)
  where visibility = 'public' and archived_at is null;

-- Public SELECT of another man's worn look. Own-row policies stay; Postgres
-- ORs policies for the same command. Default-private rows remain isolated.
drop policy if exists outfits_select_public_worn on public.outfits;
create policy outfits_select_public_worn on public.outfits
  for select to authenticated
  using (
    visibility = 'public'
    and archived_at is null
    and exists (
      select 1 from public.outfit_wears w
      where w.outfit_id = outfits.id
    )
  );

drop policy if exists outfit_items_select_public_look on public.outfit_items;
create policy outfit_items_select_public_look on public.outfit_items
  for select to authenticated
  using (
    exists (
      select 1
      from public.outfits o
      where o.id = outfit_items.outfit_id
        and o.visibility = 'public'
        and o.archived_at is null
        and exists (
          select 1 from public.outfit_wears w where w.outfit_id = o.id
        )
    )
  );

drop policy if exists closet_items_select_public_look on public.closet_items;
create policy closet_items_select_public_look on public.closet_items
  for select to authenticated
  using (
    exists (
      select 1
      from public.outfit_items oi
      join public.outfits o on o.id = oi.outfit_id
      where oi.closet_item_id = closet_items.id
        and o.visibility = 'public'
        and o.archived_at is null
        and exists (
          select 1 from public.outfit_wears w where w.outfit_id = o.id
        )
    )
  );

create or replace function public.outfits_public_requires_wear()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.visibility = 'public' then
    if not exists (
      select 1 from public.outfit_wears w where w.outfit_id = new.id
    ) then
      raise exception 'An outfit can only be public after it has been worn.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists outfits_public_requires_wear on public.outfits;
create trigger outfits_public_requires_wear
  before insert or update of visibility on public.outfits
  for each row execute function public.outfits_public_requires_wear();

revoke all on function public.outfits_public_requires_wear() from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- lookbook_reports (stub — insert only, no moderation queue yet)
-- ----------------------------------------------------------------------------
create table if not exists public.lookbook_reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references public.profiles(id) on delete cascade,
  outfit_id    uuid not null references public.outfits(id) on delete cascade,
  created_at   timestamptz not null default now(),
  unique (reporter_id, outfit_id)
);

comment on table public.lookbook_reports is
  'Stub report control for public lookbooks. One row per reporter per outfit.';

alter table public.lookbook_reports enable row level security;

drop policy if exists lookbook_reports_insert_own on public.lookbook_reports;
create policy lookbook_reports_insert_own on public.lookbook_reports
  for insert to authenticated
  with check (reporter_id = (select auth.uid()));

drop policy if exists lookbook_reports_select_own on public.lookbook_reports;
create policy lookbook_reports_select_own on public.lookbook_reports
  for select to authenticated
  using (reporter_id = (select auth.uid()));

-- ----------------------------------------------------------------------------
-- referral codes
-- ----------------------------------------------------------------------------
create or replace function public.generate_referral_code()
returns text
language plpgsql
set search_path = public
as $$
declare
  candidate text;
begin
  loop
    candidate := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (
      select 1 from public.profiles p where p.referral_code = candidate
    );
  end loop;
  return candidate;
end;
$$;

revoke all on function public.generate_referral_code() from public, anon, authenticated;

alter table public.profiles
  add column if not exists referral_code text,
  add column if not exists referred_by uuid references public.profiles(id) on delete set null;

comment on column public.profiles.referral_code is
  'Shareable code for one-guy referral. Generated on signup; not a growth dashboard.';
comment on column public.profiles.referred_by is
  'Set once via apply_referral_code. Null until he enters a code.';

alter table public.profiles
  alter column referral_code set default public.generate_referral_code();

update public.profiles
set referral_code = public.generate_referral_code()
where referral_code is null;

alter table public.profiles
  alter column referral_code set not null;

create unique index if not exists profiles_referral_code_uidx
  on public.profiles (referral_code);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, referral_code)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    public.generate_referral_code()
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Trigger-only: creates public.profiles with a referral_code on signup.';

revoke all on function public.handle_new_user() from public, anon, authenticated;

create or replace function public.apply_referral_code(p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  referrer uuid;
  already uuid;
  normalized text := upper(trim(p_code));
begin
  if me is null then
    raise exception 'Not authenticated';
  end if;
  if normalized is null or length(normalized) = 0 then
    raise exception 'Enter a code.';
  end if;

  select id into referrer
  from public.profiles
  where referral_code = normalized;

  if referrer is null then
    raise exception 'That code is not one of ours.';
  end if;
  if referrer = me then
    raise exception 'You cannot use your own code.';
  end if;

  select referred_by into already
  from public.profiles
  where id = me;

  if already is not null then
    if already = referrer then
      return;
    end if;
    raise exception 'A referral is already on this account.';
  end if;

  update public.profiles
  set referred_by = referrer
  where id = me and referred_by is null;
end;
$$;

comment on function public.apply_referral_code(text) is
  'Sets profiles.referred_by once from another man''s referral_code. Clients cannot SELECT other profiles.';

revoke all on function public.apply_referral_code(text) from public, anon;
grant execute on function public.apply_referral_code(text) to authenticated;
