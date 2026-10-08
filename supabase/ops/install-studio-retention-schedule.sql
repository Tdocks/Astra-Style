-- Hosted Supabase only: pg_cron/pg_net/Vault are not provided by scratch CI.
-- Deploy studio-retention with its custom scheduler authentication first.
-- No secret is returned or embedded in the cron command or repository.
create extension if not exists pg_cron;
create extension if not exists pg_net;
select vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'astra_studio_retention_scheduler')
  where not exists(select 1 from vault.secrets where name='astra_studio_retention_scheduler');
update public.studio_retention_config set enabled=true,
  scheduler_token_hash=encode(extensions.digest((select decrypted_secret from vault.decrypted_secrets
    where name='astra_studio_retention_scheduler'),'sha256'),'hex') where singleton;
select cron.schedule('astra-studio-retention-5m','*/5 * * * *', $cron$
  select net.http_post(
    url:='https://anutsdzbxycaavmmkewo.supabase.co/functions/v1/studio-retention',
    headers:=jsonb_build_object('Content-Type','application/json','x-astra-retention-secret',
      (select decrypted_secret from vault.decrypted_secrets where name='astra_studio_retention_scheduler')),
    body:='{}'::jsonb,timeout_milliseconds:=30000);
$cron$);
