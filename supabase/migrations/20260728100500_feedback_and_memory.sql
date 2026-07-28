-- ============================================================================
-- Astra Style — 06. Feedback & memory
-- ============================================================================
-- Tables: kyra_threads, kyra_messages, style_feedback, style_memories
-- (kyra_threads/kyra_messages are created first in this file because
-- style_memories.source_message_id references kyra_messages.)
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- kyra_threads
-- ----------------------------------------------------------------------------
create table if not exists public.kyra_threads (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  title            text,
  last_message_at  timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table public.kyra_threads is
  'A Kyra conversation (§6.20). last_message_at is maintained by touch_kyra_thread() trigger on kyra_messages insert.';

-- ----------------------------------------------------------------------------
-- kyra_messages
-- ----------------------------------------------------------------------------
-- user_id denormalized from kyra_threads.user_id, same pattern/rationale as
-- closet_item_images (see 20260728100300_closet.sql).
create table if not exists public.kyra_messages (
  id                    uuid primary key default gen_random_uuid(),
  thread_id             uuid not null references public.kyra_threads(id) on delete cascade,
  user_id               uuid not null references auth.users(id) on delete cascade,
  role                  kyra_message_role not null,
  content               text,
  structured_payload    jsonb not null default '{}'::jsonb,
  model_metadata        jsonb not null default '{}'::jsonb,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.kyra_messages is
  'One turn in a Kyra conversation. structured_payload holds the §11 response schema (cards/suggested_actions/etc.) for assistant turns.';
comment on column public.kyra_messages.model_metadata is
  'Provider/model id, token counts, latency, confidence — NOT raw prompts or provider request/response bodies. §14 explicitly requires avoiding logging full prompt contents or private images; this column must stay metadata-only.';

-- ----------------------------------------------------------------------------
-- style_feedback
-- ----------------------------------------------------------------------------
create table if not exists public.style_feedback (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  target_type   feedback_target_type not null,
  -- Intentionally polymorphic, not a foreign key: target_id may point into
  -- closet_items, outfits, outfit_items, or product_candidates depending on
  -- target_type, and Postgres has no native polymorphic FK. Referential
  -- integrity for this column is enforced at the application/Edge Function
  -- layer, not the database. This is a deliberate, documented modeling
  -- trade-off (see docs/04-data-model.md), not an oversight.
  target_id     uuid not null,
  signal        feedback_signal not null,
  reason_tags   jsonb not null default '[]'::jsonb,
  free_text     text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.style_feedback is
  'Durable feedback signal used by the §10 compatibility formula''s "historical co-wear/feedback" term (10% weight) and by Kyra''s learning loop.';
comment on column public.style_feedback.target_id is
  'Polymorphic reference; see table comment. Application code must validate target_id exists in the table implied by target_type before insert.';

-- ----------------------------------------------------------------------------
-- style_memories
-- ----------------------------------------------------------------------------
-- No archived_at/deleted_at here by design: §6.20 ("Allow users to inspect and
-- delete style memories") and §29 ("Delete individual reference and generated
-- images" / privacy posture) both frame memory removal as real deletion, not
-- hiding. A soft-delete flag would leave inferred personal preferences sitting
-- in the database against that intent, so deletion of a style memory is always
-- a hard DELETE.
create table if not exists public.style_memories (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  memory_type         memory_type not null,
  content             text not null,
  confidence          numeric(3,2) check (confidence between 0 and 1),
  source_message_id   uuid references public.kyra_messages(id) on delete set null,
  is_user_visible     boolean not null default true,
  -- vector(1536): see docs/04-data-model.md. Used to deduplicate/merge
  -- semantically similar memories before they're surfaced or added.
  embedding           extensions.vector(1536),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.style_memories is
  'Durable preferences Kyra chooses to remember across conversations (§6.20, §11 "memory_proposals"). Hard-delete only — see table-level design note.';
comment on column public.style_memories.confidence is
  'Probability-style column (0.00-1.00 numeric), distinct from the *_score integer 0-100 convention used elsewhere — see 20260728100200_profiles_and_identity.sql header.';
comment on column public.style_memories.is_user_visible is
  'False for low-confidence/internal memory candidates not yet surfaced to the "inspect your memories" UI (§6.20).';
