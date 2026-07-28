-- ============================================================================
-- Astra Style — 08. Planning
-- ============================================================================
-- Tables: occasions, daily_briefs
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- occasions
-- ----------------------------------------------------------------------------
create table if not exists public.occasions (
  id                          uuid primary key default gen_random_uuid(),
  user_id                     uuid not null references auth.users(id) on delete cascade,
  title                       text not null,
  starts_at                   timestamptz not null,
  ends_at                     timestamptz,
  location                    text,
  dress_code                  dress_code,
  source                      occasion_source not null default 'manual',
  calendar_event_identifier   text,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  check (ends_at is null or ends_at >= starts_at)
);

comment on table public.occasions is
  'A planned event feeding occasion-aware outfit generation (§5.4, §6.8, §7 EventKit sync). calendar_event_identifier links back to the EventKit event when source = calendar_sync, so a re-sync can upsert instead of duplicate.';

-- One EventKit event should not produce duplicate occasions per user on resync.
create unique index if not exists occasions_unique_calendar_event_per_user
  on public.occasions (user_id, calendar_event_identifier)
  where calendar_event_identifier is not null;

-- ----------------------------------------------------------------------------
-- daily_briefs
-- ----------------------------------------------------------------------------
create table if not exists public.daily_briefs (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references auth.users(id) on delete cascade,
  brief_date                date not null,
  primary_outfit_id         uuid references public.outfits(id) on delete set null,
  alternative_outfit_ids    jsonb not null default '[]'::jsonb,
  weather_snapshot          jsonb not null default '{}'::jsonb,
  schedule_snapshot         jsonb not null default '{}'::jsonb,
  kyra_message              text,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  constraint daily_briefs_one_per_user_per_day unique (user_id, brief_date)
);

comment on table public.daily_briefs is
  'Kyra''s Daily Brief (§6.11), one row per user per calendar day. alternative_outfit_ids is jsonb rather than a join table because the alternatives carousel is an ordered, brief-scoped list, not a queryable relationship elsewhere.';
comment on column public.daily_briefs.primary_outfit_id is
  'on delete set null (not cascade): if the referenced outfit is later removed, the historical brief record should remain readable rather than disappear.';
