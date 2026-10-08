-- Hosted scheduler extensions are absent in scratch CI. Core retention is
-- independently tested there; this installation is verified on hosted Supabase.
do $install$
begin
  if exists(select 1 from pg_extension where extname='supabase_vault')
     and exists(select 1 from pg_available_extensions where name='pg_cron')
     and exists(select 1 from pg_available_extensions where name='pg_net') then
    execute $sql$create extension if not exists pg_cron$sql$;
    execute $sql$create extension if not exists pg_net$sql$;
    execute $sql$select vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'astra_studio_retention_scheduler')
  where not exists(select 1 from vault.secrets where name='astra_studio_retention_scheduler')$sql$;
    execute $sql$update public.studio_retention_config set enabled=true,
  scheduler_token_hash=encode(extensions.digest((select decrypted_secret from vault.decrypted_secrets
    where name='astra_studio_retention_scheduler'),'sha256'),'hex') where singleton$sql$;
    execute $sql$select cron.schedule('astra-studio-retention-5m','*/5 * * * *', $cron$
  select net.http_post(
    url:='https://anutsdzbxycaavmmkewo.supabase.co/functions/v1/studio-retention',
    headers:=jsonb_build_object('Content-Type','application/json','x-astra-retention-secret',
      (select decrypted_secret from vault.decrypted_secrets where name='astra_studio_retention_scheduler')),
    body:='{}'::jsonb,timeout_milliseconds:=30000);
$cron$)$sql$;
  end if;
end;
$install$;
