-- Cross-session proof that a per-user enqueue lock coalesces equivalent inputs
-- submitted with distinct transport keys.
create extension if not exists dblink with schema extensions;
create table public.p6_studio_cache_concurrency_fixture(user_id uuid primary key);
insert into auth.users(id,email)
  select gen_random_uuid(),'p6-cache-concurrency-'||gen_random_uuid()||'@invalid.test';
insert into public.p6_studio_cache_concurrency_fixture(user_id)
  select id from auth.users where email like 'p6-cache-concurrency-%@invalid.test';

create function public.p6_studio_cache_concurrency_delay() returns trigger
language plpgsql as $$
begin
  if exists(select 1 from public.p6_studio_cache_concurrency_fixture where user_id=new.user_id) then
    perform pg_sleep(1.5);
  end if;
  return new;
end;
$$;
create trigger p6_studio_cache_concurrency_delay
  after insert on public.studio_generations
  for each row execute function public.p6_studio_cache_concurrency_delay();

do $$
declare
  u uuid; semantic_key text:=repeat('c',64); key_one uuid:=gen_random_uuid(); key_two uuid:=gen_random_uuid();
  hash_one text:=repeat('1',64); hash_two text:=repeat('2',64); conninfo text; query_one text; query_two text;
  first_id text; second_id text; busy_one integer; busy_two integer; wait_started timestamptz;
begin
  select user_id into strict u from public.p6_studio_cache_concurrency_fixture;
  conninfo:=format('host=127.0.0.1 port=%s user=%s dbname=%s',current_setting('port'),current_user,current_database());
  perform extensions.dblink_connect('p6-cache-one',conninfo);
  perform extensions.dblink_connect('p6-cache-two',conninfo);
  query_one:=format('select id::text from public.enqueue_studio_generation_cached(%L::uuid,%L,%L::uuid,%L,%L,null,%L::jsonb,%L)',
    u,semantic_key,key_one,hash_one,null,'{"mode":"inspiration"}','fixture');
  query_two:=format('select id::text from public.enqueue_studio_generation_cached(%L::uuid,%L,%L::uuid,%L,%L,null,%L::jsonb,%L)',
    u,semantic_key,key_two,hash_two,null,'{"mode":"inspiration"}','fixture');
  if extensions.dblink_send_query('p6-cache-one',query_one)<>1 then raise exception 'Could not dispatch first concurrent submission'; end if;
  wait_started:=clock_timestamp();
  loop
    exit when exists(select 1 from pg_stat_activity where state='active' and query like '%enqueue_studio_generation_cached%' and pid<>pg_backend_pid());
    if clock_timestamp()-wait_started>interval '5 seconds' then raise exception 'First submission never entered the enqueue function'; end if;
    perform pg_sleep(0.01);
  end loop;
  if extensions.dblink_send_query('p6-cache-two',query_two)<>1 then raise exception 'Could not dispatch second concurrent submission'; end if;
  wait_started:=clock_timestamp();
  loop
    busy_one:=extensions.dblink_is_busy('p6-cache-one');
    busy_two:=extensions.dblink_is_busy('p6-cache-two');
    exit when busy_one=0 and busy_two=0;
    if clock_timestamp()-wait_started>interval '5 seconds' then raise exception 'Concurrent submissions did not finish within five seconds'; end if;
    perform pg_sleep(0.02);
  end loop;
  select id into strict first_id from extensions.dblink_get_result('p6-cache-one') as result(id text);
  perform * from extensions.dblink_get_result('p6-cache-one') as result(id text);
  select id into strict second_id from extensions.dblink_get_result('p6-cache-two') as result(id text);
  perform * from extensions.dblink_get_result('p6-cache-two') as result(id text);
  if first_id<>second_id then raise exception 'Concurrent equivalent requests created separate generations'; end if;
  if (select count(*) from public.studio_generations where user_id=u and cache_key=semantic_key)<>1 then
    raise exception 'Concurrent equivalent requests did not produce exactly one generation'; end if;
  if (select count(*) from public.studio_allowances where user_id=u and released_at is null)<>1 then
    raise exception 'Concurrent coalesced requests reserved multiple allowances'; end if;
  if (select count(*) from public.studio_submission_requests where user_id=u and generation_id=first_id::uuid)<>2 then
    raise exception 'Distinct transport keys were not both mapped to the shared generation'; end if;
  perform extensions.dblink_disconnect('p6-cache-one');
  perform extensions.dblink_disconnect('p6-cache-two');
end;
$$;

drop trigger p6_studio_cache_concurrency_delay on public.studio_generations;
drop function public.p6_studio_cache_concurrency_delay();
delete from auth.users where id in(select user_id from public.p6_studio_cache_concurrency_fixture);
drop table public.p6_studio_cache_concurrency_fixture;
drop extension dblink;
