-- Consumer JWTs have no scheduler role. The hosted extension defaults include
-- PUBLIC policies/grants; keep scheduling and its command/history metadata
-- available only to the database owner. Scratch CI does not install pg_cron.
do $$
begin
  if exists(select 1 from pg_namespace where nspname='cron') then
    execute 'revoke all on all tables in schema cron from public,anon,authenticated';
    execute 'revoke all on all sequences in schema cron from public,anon,authenticated';
    execute 'revoke all on all functions in schema cron from public,anon,authenticated';
    execute 'revoke all on schema cron from public,anon,authenticated';
  end if;
end;
$$;
