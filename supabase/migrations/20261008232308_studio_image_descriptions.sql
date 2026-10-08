-- Only the accessibility description is client editable; job/lease/credit
-- fields retain their server-only column privileges.
alter table public.studio_generations add column alt_description text
  check (alt_description is null or (char_length(btrim(alt_description)) between 1 and 1000));
grant update(alt_description) on public.studio_generations to authenticated;
create policy studio_description_update_own on public.studio_generations
  for update to authenticated
  using ((select auth.uid())=user_id and status='complete' and deleted_at is null)
  with check ((select auth.uid())=user_id and status='complete' and deleted_at is null);
