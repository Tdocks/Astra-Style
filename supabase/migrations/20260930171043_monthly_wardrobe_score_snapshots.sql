-- Preserve one real Wardrobe Score versatility snapshot per user and month so
-- Monthly Review can compare recorded months instead of inventing a trend.
create table public.wardrobe_score_monthly_snapshots (
  user_id uuid not null references auth.users(id) on delete cascade,
  month_start date not null,
  versatility_score smallint not null check (versatility_score between 0 and 100),
  captured_at timestamptz not null default now(),
  primary key (user_id, month_start),
  constraint wardrobe_score_monthly_snapshots_month_start_check
    check (extract(day from month_start) = 1)
);

comment on table public.wardrobe_score_monthly_snapshots is
  'The caller-scoped versatility score captured when Monthly Review is opened. The first saved month establishes a baseline; later months can report a real change.';

alter table public.wardrobe_score_monthly_snapshots enable row level security;

create policy wardrobe_score_monthly_snapshots_select_own
  on public.wardrobe_score_monthly_snapshots for select to authenticated
  using (user_id = (select auth.uid()));

create policy wardrobe_score_monthly_snapshots_insert_own
  on public.wardrobe_score_monthly_snapshots for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy wardrobe_score_monthly_snapshots_update_own
  on public.wardrobe_score_monthly_snapshots for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy wardrobe_score_monthly_snapshots_delete_own
  on public.wardrobe_score_monthly_snapshots for delete to authenticated
  using (user_id = (select auth.uid()));

grant select, insert, update, delete on public.wardrobe_score_monthly_snapshots to authenticated;
