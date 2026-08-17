-- ============================================================================
-- Astra Style — analytics_events
-- ============================================================================
-- Closes completion-plan gate G3 (`docs/17-completion-plan.md`): before this
-- migration, `LiveAnalyticsClient.log()` was a DEBUG print and no table
-- existed for it to write to, so every event the app constructs (spec §18's
-- list, `ios/AstraStyle/Core/Analytics/AnalyticsEvent.swift`) went nowhere.
-- Nothing shipped from here was measurable.
--
-- THIS TABLE IS DESIGNED TO PASS P7-PRIVACY-07 BY CONSTRUCTION, NOT BY AUDIT.
-- `P7-PRIVACY-07` (`docs/02-task-breakdown.md`) is a later ticket that greps
-- production-equivalent logs and `analytics_events` for image URLs or raw
-- prompt text. A table whose shape simply cannot hold that content makes the
-- audit a formality instead of a remediation project. Two layers do this:
--
--   1. `event_name analytics_event_name` — a closed enum mirroring
--      `AnalyticsEvent.name`'s 16 cases exactly (spec §18's "Key events"
--      list), not `text`. A client cannot insert an event name that isn't
--      one of the 16 the product actually defines, and adding a 17th
--      requires a migration, which is the correct amount of friction for
--      "a new kind of fact gets recorded about every user forever."
--   2. `properties jsonb` constrained by `analytics_event_properties_is_shallow`
--      (below) to a FLAT object of short scalars/short-scalar-arrays. This is
--      the load-bearing part: `AnalyticsEvent.properties`
--      (`ios/AstraStyle/Core/Analytics/AnalyticsEvent.swift`) already only
--      ever emits enum raw values, counts, booleans, and UUIDs by
--      construction, so today this constraint is redundant with the Swift
--      type on every path that exists. It is here anyway as the
--      defense-in-depth backstop spec §18 asks for ("do not expose sensitive
--      images or free-text prompts") — if a future event ever tried to smuggle
--      a garment name, an email address, or a raw Kyra prompt through
--      `properties`, the INSERT fails at the database instead of quietly
--      succeeding and waiting for P7-PRIVACY-07 to find it in production
--      months later. A 64-character cap on every string comfortably fits
--      every real value the app sends today (uuids, enum tags, retailer
--      names, StoreKit product ids all top out well under that) while
--      firmly rejecting the shapes that would actually carry PII, which run
--      to sentences and paragraphs, not tags.
--
-- WHY `select-own` IS GRANTED (a real decision, not an oversight)
-- ------------------------------------------------------------------
-- Every other user-owned table in this schema (`kyra_messages`,
-- `style_memories`, `style_feedback`, ...) grants the owner select, and the
-- two tables that deliberately withhold it — `subscriptions`,
-- `account_deletions` — do so because they are written by a service-role
-- process the client must never race or spoof, not because reading them is
-- dangerous. `analytics_events` doesn't share that reason: it is written by
-- the client itself (same shape as `style_feedback`/`outfit_wears`), so
-- there is no privileged writer to protect from a client read racing it.
-- And because `properties` is constrained to non-PII by design (see above),
-- there is no privacy argument for hiding a user's own behavioural log from
-- them either — the whole point of RLS here is that user A can never see
-- user B's rows, not that user A can't see their own. Withholding select
-- would only ever cost a legitimate future use (an in-app "your activity"
-- view, or answering the row's own §29 data-export requirement straight
-- from Postgrest) for no isolation benefit, so it is granted.
--
-- WHY NO update/delete POLICY
-- -----------------------------
-- An event is a fact about something that already happened ("this outfit was
-- marked worn at 14:02"); it doesn't get corrected in place; the north-star
-- metrics in spec §18 (weekly-active, activation counts) are aggregates over
-- a period, and an interior row silently changing shape after being counted
-- once already contradicts this repo's "absent is honest; a confounded
-- reading is not" rule harder than a merely-missing event does. So this
-- table is append-only from the client's perspective: no `authenticated`
-- update/delete policy exists at all. (Account deletion still removes every
-- row via the `auth.users` cascade — see
-- `20260728101300_account_deletion.sql` — so a deleted user's events do not
-- outlive their account.)
--
-- Append-only migration: do not edit once applied.
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- analytics_event_name — closed enum, mirrors AnalyticsEvent.name exactly.
-- ----------------------------------------------------------------------------
do $$ begin
  create type analytics_event_name as enum (
    'onboarding_started',
    'onboarding_completed',
    'closet_item_added',
    'scan_corrected',
    'outfit_generated',
    'outfit_marked_worn',
    'outfit_rejected',
    'kyra_prompt_sent',
    'product_evaluated',
    'affiliate_link_opened',
    'studio_generation_started',
    'studio_generation_completed',
    'paywall_viewed',
    'subscription_started',
    'subscription_renewed',
    'subscription_cancelled'
  );
exception when duplicate_object then null; end $$;

comment on type analytics_event_name is
  'Mirrors AnalyticsEvent.name in ios/AstraStyle/Core/Analytics/AnalyticsEvent.swift, spec §18''s "Key events" list. Adding an event requires a migration on purpose — see table header.';

-- ----------------------------------------------------------------------------
-- analytics_event_properties_is_shallow — the PII backstop (see header).
-- ----------------------------------------------------------------------------
-- Accepts a jsonb OBJECT whose values are each one of:
--   null | boolean | number | string (<= 64 chars)
--   | array (<= 10 elements) of null | boolean | number | string (<= 64 chars)
-- Rejects everything else, in particular a nested object/array-of-objects at
-- any depth and any string over 64 characters — the two shapes a pasted
-- prompt, an email address, or an image path would actually take.
create or replace function public.analytics_event_properties_is_shallow(p jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key   text;
  v_value jsonb;
  v_elem  jsonb;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    return false;
  end if;

  for v_key, v_value in select * from jsonb_each(p) loop
    case jsonb_typeof(v_value)
      when 'null', 'boolean', 'number' then
        -- Always acceptable; nothing free-text-shaped can hide in a number
        -- or a boolean.
        null;
      when 'string' then
        if char_length(v_value #>> '{}') > 64 then
          return false;
        end if;
      when 'array' then
        if jsonb_array_length(v_value) > 10 then
          return false;
        end if;
        for v_elem in select * from jsonb_array_elements(v_value) loop
          if jsonb_typeof(v_elem) not in ('null', 'boolean', 'number', 'string') then
            -- No arrays-of-objects/arrays-of-arrays: one level of nesting
            -- (object -> array of scalars) is as deep as a legitimate
            -- property (e.g. outfit_rejected's reason_tags) ever needs to go.
            return false;
          end if;
          if jsonb_typeof(v_elem) = 'string' and char_length(v_elem #>> '{}') > 64 then
            return false;
          end if;
        end loop;
      else
        -- 'object': a nested object is exactly the shape a free-form blob
        -- would take to smuggle itself past a shallow scan. Reject it.
        return false;
    end case;
  end loop;

  return true;
end;
$$;

comment on function public.analytics_event_properties_is_shallow(jsonb) is
  'CHECK-constraint backstop for analytics_events.properties — see that table''s header comment for what this rejects and why.';

-- ----------------------------------------------------------------------------
-- analytics_events
-- ----------------------------------------------------------------------------
create table if not exists public.analytics_events (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  event_name   analytics_event_name not null,
  -- Non-sensitive metadata only — see analytics_event_properties_is_shallow.
  properties   jsonb not null default '{}'::jsonb,
  -- Client-observed event time. Distinct from created_at (server receipt
  -- time) because `LiveAnalyticsClient` batches and queues offline (spec
  -- §7) — a event logged while offline and delivered an hour later must
  -- keep the moment it actually happened, not the moment the batch finally
  -- reached Postgrest, or every offline session would misreport its own
  -- timeline in the north-star metrics (spec §18).
  occurred_at  timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  constraint analytics_events_properties_shape
    check (public.analytics_event_properties_is_shallow(properties))
);

comment on table public.analytics_events is
  'Client-emitted product analytics (spec §18). Append-only — see this file''s header for the select-own/no-update-delete RLS rationale and the PII-shape guarantee on properties.';
comment on column public.analytics_events.occurred_at is
  'Client-observed event time (may be well before created_at for an event delivered from LiveAnalyticsClient''s offline backlog). Use this, not created_at, for any time-series/cohort metric.';
comment on column public.analytics_events.created_at is
  'Server receipt time. Useful for measuring offline-delivery latency (created_at - occurred_at), not for the metric itself.';

create index if not exists idx_analytics_events_user_id_occurred_at
  on public.analytics_events (user_id, occurred_at desc);

create index if not exists idx_analytics_events_event_name_occurred_at
  on public.analytics_events (event_name, occurred_at desc);

alter table public.analytics_events enable row level security;

drop policy if exists analytics_events_select_own on public.analytics_events;
create policy analytics_events_select_own on public.analytics_events
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists analytics_events_insert_own on public.analytics_events;
create policy analytics_events_insert_own on public.analytics_events
  for insert to authenticated
  with check (user_id = (select auth.uid()));

-- No update/delete policy for `authenticated` — see header "WHY NO
-- update/delete POLICY". Rows are removed only via the auth.users cascade
-- (account deletion).
