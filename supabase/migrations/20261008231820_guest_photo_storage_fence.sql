-- ADR 0018: guest photo bytes remain on-device until Apple/email linking.
-- Anonymous Auth users are also authenticated; ownership alone is insufficient.
-- Read access remains available for server-generated guest inspiration images.
create policy user_content_permanent_insert on storage.objects as restrictive for insert to authenticated
  with check(bucket_id<>'user-content' or (select (auth.jwt()->>'is_anonymous')::boolean) is false);
create policy user_content_permanent_update on storage.objects as restrictive for update to authenticated
  using(bucket_id<>'user-content' or (select (auth.jwt()->>'is_anonymous')::boolean) is false)
  with check(bucket_id<>'user-content' or (select (auth.jwt()->>'is_anonymous')::boolean) is false);
