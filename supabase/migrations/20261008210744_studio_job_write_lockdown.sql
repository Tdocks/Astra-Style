-- Deploy the new Studio Edge Function before this lockdown.
-- Fill any legacy jobs created between expansion and rollout.
insert into public.studio_allowances(id,user_id,created_at,consumed_at,released_at,latest_generation_id)
select id,user_id,created_at,
 case when status='complete' then updated_at end,
 case when status='failed' and coalesce(prompt_payload->>'is_retryable_failure','false') <> 'true' then updated_at end,id
from public.studio_generations where allowance_id is null;
update public.studio_generations set allowance_id=id where allowance_id is null;
alter table public.studio_generations alter column allowance_id set not null;

drop policy if exists studio_generations_insert_own on public.studio_generations;
drop policy if exists studio_generations_update_own on public.studio_generations;
drop policy if exists studio_generations_delete_own on public.studio_generations;
revoke insert, update on public.studio_generations from public, anon, authenticated;
grant select, delete on public.studio_generations to authenticated;
create policy studio_generations_delete_own on public.studio_generations
  for delete to authenticated using (user_id=(select auth.uid()) and status in ('complete','failed'));
