-- Cover composite child-key lookups used by the ON DELETE CASCADE checks.
-- The partial pending-confirmation unique index intentionally cannot cover
-- closed confirmations, which remain until their parent message/thread goes.
create index if not exists kyra_studio_confirmations_thread_user_fk_idx
  on public.kyra_studio_confirmations (thread_id, user_id);

create index if not exists kyra_studio_confirmations_prompt_message_thread_user_fk_idx
  on public.kyra_studio_confirmations (prompt_message_id, thread_id, user_id);

-- Submission requests are keyed by (user_id, request_key); this separate
-- index lets generation deletion find all idempotency records efficiently.
create index if not exists studio_submission_requests_generation_user_fk_idx
  on public.studio_submission_requests (generation_id, user_id);
