-- ============================================================================
-- Astra Style — 13. Functions & triggers
-- ============================================================================
-- Contents:
--   1. set_updated_at() — generic updated_at maintenance, attached to every
--      table via a loop.
--   2. handle_new_user() — creates the profiles row on auth signup (§7 "Guest
--      migration to account" / standard onboarding entry point).
--   3. Denormalized-user_id trigger family — populates + guards user_id on
--      closet_item_images, outfit_items, kyra_messages from their parent row.
--   4. touch_kyra_thread() — keeps kyra_threads.last_message_at current.
--   5. bump_closet_item_wear_stats() — updates wear_count/last_worn_at on
--      "mark worn" (§6.15, §5.2), feeding cost-per-wear calculations.
--   6. archive_closet_item() / restore_closet_item() — the soft-delete
--      convention's public RPC surface for closet_items.archived_at.
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- 1. updated_at maintenance
-- ----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'Generic BEFORE UPDATE trigger: stamps updated_at = now() on every row change. Attached to every table below via a loop rather than one CREATE TRIGGER per table.';

do $$
declare
  t text;
  updated_at_tables text[] := array[
    'profiles', 'style_profiles', 'body_profiles', 'lifestyle_profiles',
    'closet_items', 'closet_item_images',
    'outfits', 'outfit_items', 'outfit_wears',
    'style_feedback', 'style_memories',
    'kyra_threads', 'kyra_messages',
    'product_candidates', 'user_product_evaluations',
    'occasions', 'daily_briefs',
    'studio_generations', 'subscriptions'
  ];
begin
  foreach t in array updated_at_tables loop
    execute format('drop trigger if exists trg_set_updated_at on public.%I', t);
    execute format(
      'create trigger trg_set_updated_at before update on public.%I for each row execute function public.set_updated_at()',
      t
    );
  end loop;
end
$$;

-- ----------------------------------------------------------------------------
-- 2. handle_new_user — creates the profile row on signup.
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Trigger-only: fires after a row is inserted into auth.users (Sign in with Apple, email OTP/magic link, or guest->account migration, §7) and creates the matching public.profiles row. SECURITY DEFINER because the inserting session (GoTrue) has no direct grant on public.profiles.';

-- Supabase grants EXECUTE on every newly created public-schema function to
-- anon/authenticated by default (ALTER DEFAULT PRIVILEGES set at project
-- bootstrap) — `revoke ... from public` alone does NOT undo that, since it
-- was granted to those roles directly, not inherited through PUBLIC. Every
-- REVOKE in this file and in 20260728101300_account_deletion.sql therefore
-- names anon/authenticated explicitly, confirmed against this behavior in
-- manual verification (see docs/04-data-model.md).
revoke all on function public.handle_new_user() from public, anon, authenticated;

do $$
begin
  if to_regclass('auth.users') is null then
    raise notice 'auth.users not found (not a Supabase project) — skipping on_auth_user_created trigger.';
    return;
  end if;

  drop trigger if exists on_auth_user_created on auth.users;
  create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();
end
$$;

-- ----------------------------------------------------------------------------
-- 3. Denormalized-user_id trigger family
-- ----------------------------------------------------------------------------
-- Each function below fires BEFORE INSERT, looks up the owning user_id from
-- the parent row, and overwrites NEW.user_id with it — regardless of what the
-- client sent. These functions are deliberately plain SECURITY INVOKER (the
-- default), not SECURITY DEFINER, so their internal SELECT against the parent
-- table is itself subject to that parent table's RLS as the calling user.
-- Two effects fall out of this:
--   a) The client never has to (and cannot usefully) supply user_id directly.
--   b) If the referenced parent (closet_item_id / outfit_id / thread_id)
--      belongs to a *different* user than the caller, the invoker-rights
--      SELECT inside the trigger can't see that row at all (RLS filters it
--      out), so NEW.user_id stays null and the trigger raises immediately —
--      "insert a child row against someone else's parent" fails at the
--      trigger's own existence check, before the outer table's
--      `..._insert_own` WITH CHECK (user_id = (select auth.uid())) even runs.
--      Verified in manual testing: see docs/04-data-model.md verification
--      notes. Had these functions instead been SECURITY DEFINER (bypassing
--      the parent's RLS), the same cross-owner insert would still be caught,
--      just one layer later, by the WITH CHECK on this table.
-- Ownership is treated as immutable after creation (an image is not
-- reassigned to a different closet item, an outfit_item is not moved to a
-- different outfit, a message is not moved to a different thread), so these
-- fire on INSERT only, not UPDATE.

create or replace function public.set_user_id_from_closet_item()
returns trigger
language plpgsql
as $$
begin
  select user_id into new.user_id
  from public.closet_items
  where id = new.closet_item_id;

  if new.user_id is null then
    raise exception 'closet_item_id % does not reference an existing closet item', new.closet_item_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_closet_item_images_set_user_id on public.closet_item_images;
create trigger trg_closet_item_images_set_user_id
  before insert on public.closet_item_images
  for each row execute function public.set_user_id_from_closet_item();

create or replace function public.set_user_id_from_outfit()
returns trigger
language plpgsql
as $$
begin
  select user_id into new.user_id
  from public.outfits
  where id = new.outfit_id;

  if new.user_id is null then
    raise exception 'outfit_id % does not reference an existing outfit', new.outfit_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_outfit_items_set_user_id on public.outfit_items;
create trigger trg_outfit_items_set_user_id
  before insert on public.outfit_items
  for each row execute function public.set_user_id_from_outfit();

create or replace function public.set_user_id_from_kyra_thread()
returns trigger
language plpgsql
as $$
begin
  select user_id into new.user_id
  from public.kyra_threads
  where id = new.thread_id;

  if new.user_id is null then
    raise exception 'thread_id % does not reference an existing kyra thread', new.thread_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_kyra_messages_set_user_id on public.kyra_messages;
create trigger trg_kyra_messages_set_user_id
  before insert on public.kyra_messages
  for each row execute function public.set_user_id_from_kyra_thread();

-- ----------------------------------------------------------------------------
-- 4. touch_kyra_thread — keep kyra_threads.last_message_at current.
-- ----------------------------------------------------------------------------
create or replace function public.touch_kyra_thread()
returns trigger
language plpgsql
as $$
begin
  update public.kyra_threads
  set last_message_at = new.created_at
  where id = new.thread_id;

  return new;
end;
$$;

drop trigger if exists trg_kyra_messages_touch_thread on public.kyra_messages;
create trigger trg_kyra_messages_touch_thread
  after insert on public.kyra_messages
  for each row execute function public.touch_kyra_thread();

-- ----------------------------------------------------------------------------
-- 5. bump_closet_item_wear_stats — "mark worn" side effects.
-- ----------------------------------------------------------------------------
create or replace function public.bump_closet_item_wear_stats()
returns trigger
language plpgsql
as $$
begin
  update public.closet_items ci
  set wear_count = ci.wear_count + 1,
      last_worn_at = greatest(coalesce(ci.last_worn_at, new.worn_at), new.worn_at)
  from public.outfit_items oi
  where oi.outfit_id = new.outfit_id
    and oi.closet_item_id = ci.id
    and ci.user_id = new.user_id;

  return new;
end;
$$;

comment on function public.bump_closet_item_wear_stats() is
  'On outfit_wears insert, increments wear_count and advances last_worn_at for every owned closet_item in that outfit. Feeds cost_per_wear = price_paid / wear_count, computed at read time by the client/API rather than stored (see docs/04-data-model.md).';

drop trigger if exists trg_outfit_wears_bump_stats on public.outfit_wears;
create trigger trg_outfit_wears_bump_stats
  after insert on public.outfit_wears
  for each row execute function public.bump_closet_item_wear_stats();

-- ----------------------------------------------------------------------------
-- 6. Soft-delete convention: archive_closet_item / restore_closet_item.
-- ----------------------------------------------------------------------------
create or replace function public.archive_closet_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.closet_items
  set archived_at = now(),
      availability_state = 'unavailable'
  where id = p_item_id
    and user_id = (select auth.uid())
    and archived_at is null;

  if not found then
    raise exception 'closet item % not found, already archived, or not owned by the current user', p_item_id;
  end if;
end;
$$;

comment on function public.archive_closet_item(uuid) is
  'Soft-delete RPC for §6.15 "Archive" action. SECURITY DEFINER so it can run the ownership check itself and return a clear error instead of relying solely on RLS to silently no-op an unauthorized call; auth.uid() (not a client-supplied user id) is the only identity source.';

revoke all on function public.archive_closet_item(uuid) from public, anon, authenticated;
grant execute on function public.archive_closet_item(uuid) to authenticated;

create or replace function public.restore_closet_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.closet_items
  set archived_at = null,
      availability_state = 'available'
  where id = p_item_id
    and user_id = (select auth.uid())
    and archived_at is not null;

  if not found then
    raise exception 'closet item % not found, not archived, or not owned by the current user', p_item_id;
  end if;
end;
$$;

comment on function public.restore_closet_item(uuid) is
  'Reverses archive_closet_item(). availability_state is reset to available; the caller/Edge Function is responsible for re-checking laundry_state if that matters for the specific flow.';

revoke all on function public.restore_closet_item(uuid) from public, anon, authenticated;
grant execute on function public.restore_closet_item(uuid) to authenticated;
