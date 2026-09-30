-- Cover child-side foreign-key lookups used by parent deletes/updates and by
-- the corresponding list/report queries. The nullable keys use partial
-- indexes so rows without a reference do not consume index space.

create index if not exists idx_daily_briefs_primary_outfit_id
  on public.daily_briefs (primary_outfit_id)
  where primary_outfit_id is not null;

create index if not exists idx_lookbook_reports_outfit_id
  on public.lookbook_reports (outfit_id);

create index if not exists idx_profiles_referred_by
  on public.profiles (referred_by)
  where referred_by is not null;

create index if not exists idx_wishlist_items_product_candidate_id
  on public.wishlist_items (product_candidate_id);
