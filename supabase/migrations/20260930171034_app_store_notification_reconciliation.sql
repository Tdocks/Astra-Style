-- Preserve the newest verified App Store state across webhook and client
-- sync races. Pending rows cover notifications delivered before a user has
-- first opened the app and associated a transaction with their account.

alter table public.subscriptions
  add column if not exists app_store_last_signed_at timestamptz not null default 'epoch',
  add column if not exists app_store_last_notification_uuid text;

create table if not exists public.pending_app_store_notifications (
  app_store_original_transaction_id text primary key,
  notification_uuid text not null unique,
  product_id text not null,
  status public.subscription_status not null,
  expires_at timestamptz,
  environment public.subscription_environment not null,
  signed_at timestamptz not null,
  created_at timestamptz not null default now()
);

comment on table public.pending_app_store_notifications is
  'Latest verified App Store state awaiting the first authenticated device sync for an original transaction lineage. Contains no signed payload and is deleted once linked to a user.';

alter table public.pending_app_store_notifications enable row level security;
revoke all on public.pending_app_store_notifications from public, anon, authenticated;
grant all on public.pending_app_store_notifications to service_role;

create or replace function public.keep_newest_app_store_subscription_state()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.app_store_last_signed_at <= old.app_store_last_signed_at then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.keep_newest_app_store_subscription_state() from public, anon, authenticated;

drop trigger if exists subscriptions_keep_newest_app_store_state on public.subscriptions;
create trigger subscriptions_keep_newest_app_store_state
before update on public.subscriptions
for each row execute function public.keep_newest_app_store_subscription_state();

create or replace function public.keep_newest_pending_app_store_notification()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.signed_at <= old.signed_at then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.keep_newest_pending_app_store_notification() from public, anon, authenticated;

drop trigger if exists pending_app_store_keep_newest on public.pending_app_store_notifications;
create trigger pending_app_store_keep_newest
before update on public.pending_app_store_notifications
for each row execute function public.keep_newest_pending_app_store_notification();

create index if not exists idx_pending_app_store_notifications_created_at
  on public.pending_app_store_notifications (created_at);
