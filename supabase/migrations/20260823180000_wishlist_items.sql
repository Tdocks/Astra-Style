-- ============================================================================
-- P6-SHOP-07 — wishlist / purchased
-- ============================================================================
-- Owner-scoped join to the shared product_candidates catalog. `purchased_at`
-- is null while the row is a save, and set when he marks it bought. One
-- unique (user_id, product_candidate_id) so save and purchase cannot fork.
-- ============================================================================

set search_path = public, extensions;

create table if not exists public.wishlist_items (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references auth.users(id) on delete cascade,
  product_candidate_id   uuid not null references public.product_candidates(id) on delete cascade,
  purchased_at           timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint wishlist_items_user_candidate_unique unique (user_id, product_candidate_id)
);

comment on table public.wishlist_items is
  'Saved or purchased catalog rows for one user (spec §5.5 step 6, §6.18). purchased_at null = wishlist.';
comment on column public.wishlist_items.purchased_at is
  'Set when he marks the item bought. Null rows are the live wishlist.';

alter table public.wishlist_items enable row level security;

drop policy if exists wishlist_items_select_own on public.wishlist_items;
create policy wishlist_items_select_own on public.wishlist_items
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists wishlist_items_insert_own on public.wishlist_items;
create policy wishlist_items_insert_own on public.wishlist_items
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists wishlist_items_update_own on public.wishlist_items;
create policy wishlist_items_update_own on public.wishlist_items
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists wishlist_items_delete_own on public.wishlist_items;
create policy wishlist_items_delete_own on public.wishlist_items
  for delete to authenticated
  using (user_id = (select auth.uid()));
