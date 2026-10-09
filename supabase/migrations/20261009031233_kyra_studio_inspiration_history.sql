-- Keep only an opaque Studio generation reference on the user message. The
-- Kyra request path revalidates ownership and liveness before every replay.
alter table public.kyra_messages
  add column studio_generation_id uuid
  references public.studio_generations(id) on delete set null;

create index kyra_messages_studio_generation_id_idx
  on public.kyra_messages(studio_generation_id)
  where studio_generation_id is not null;

comment on column public.kyra_messages.studio_generation_id is
  'Opaque Studio generation reference for bounded Kyra provider history; resolve ownership, status, retention, and storage availability on every use. Never store image URLs or object paths here.';
