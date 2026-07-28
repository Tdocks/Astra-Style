-- ============================================================================
-- Astra Style — 09. Style Studio & subscriptions
-- ============================================================================
-- Tables: studio_generations, subscriptions
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- studio_generations
-- ----------------------------------------------------------------------------
create table if not exists public.studio_generations (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references auth.users(id) on delete cascade,
  reference_image_path     text,
  outfit_id                uuid references public.outfits(id) on delete set null,
  prompt_payload           jsonb not null default '{}'::jsonb,
  status                   generation_status not null default 'queued',
  result_image_path        text,
  -- Provider is deliberately `text`, not an enum: §8/ADR 0004 requires a
  -- provider-neutral server interface where "provider selection is a
  -- server-side configuration concern, changeable without an app release."
  -- An enum would force a schema migration every time a new image-generation
  -- vendor is added or swapped, defeating that goal.
  provider                 text,
  error_message            text,
  -- Soft delete: §6.17 "Provide deletion controls" and §13 "Delete abandoned
  -- source images after configurable retention" both require removability.
  -- deleted_at marks a generation for purge; the actual storage object
  -- deletion happens via the Storage API from an Edge Function/scheduled job,
  -- which then hard-deletes the row once objects are confirmed removed.
  deleted_at               timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

comment on table public.studio_generations is
  'One Style Studio generation job (§6.17, §13). reference_image_path/result_image_path are private-bucket storage paths under users/{user_id}/studio/ and users/{user_id}/references/, never public URLs.';
comment on column public.studio_generations.status is
  'Queued -> Generating -> Complete|Failed, per §6.17 "Generation states". Failed jobs preserve prompt_payload so the client can retry without re-submitting (§21: "Preserve prompt and allow retry without consuming another credit when failure is provider-side").';

-- ----------------------------------------------------------------------------
-- subscriptions
-- ----------------------------------------------------------------------------
-- Current-state table (one row per subscription lineage), not an event log:
-- POST /subscriptions/sync and POST /app-store/webhook (§14) upsert this row
-- keyed on app_store_original_transaction_id, which is the durable identity
-- Apple assigns to a subscription across renewals.
create table if not exists public.subscriptions (
  id                                    uuid primary key default gen_random_uuid(),
  user_id                               uuid not null references auth.users(id) on delete cascade,
  app_store_original_transaction_id     text not null,
  product_id                            text not null,
  status                                subscription_status not null,
  expires_at                            timestamptz,
  environment                           subscription_environment not null default 'production',
  created_at                            timestamptz not null default now(),
  updated_at                            timestamptz not null default now(),
  constraint subscriptions_original_transaction_id_unique unique (app_store_original_transaction_id)
);

comment on table public.subscriptions is
  'Server-reconciled StoreKit 2 entitlement state (§16). Written only by Edge Functions holding the service-role key (App Store webhook + client-triggered sync); see rls_policies.sql for the read-only-to-owner policy.';
comment on column public.subscriptions.app_store_original_transaction_id is
  'Apple''s durable subscription identity, stable across renewals/plan changes within the same subscription group purchase — the natural upsert key, unlike transaction_id which changes every renewal.';
