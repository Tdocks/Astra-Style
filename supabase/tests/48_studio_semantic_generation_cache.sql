begin;
do $$
declare
  u uuid:=gen_random_uuid(); peer uuid:=gen_random_uuid(); ref uuid:=gen_random_uuid();
  cached uuid:=gen_random_uuid(); stale uuid:=gen_random_uuid(); pending uuid:=gen_random_uuid(); rerolled uuid;
  cached_allowance uuid:=gen_random_uuid(); pending_allowance uuid:=gen_random_uuid();
  cache_key text:=encode(extensions.digest('semantic render v1','sha256'),'hex');
  reroll_key text:=encode(extensions.digest('explicit reroll v1','sha256'),'hex');
  v_request_key uuid:=gen_random_uuid(); request_hash text:=encode(extensions.digest('request','sha256'),'hex');
  reference_path text; output_path text; row public.studio_generations; before_allowances integer;
begin
  insert into auth.users(id,email) values(u,u||'@cache.invalid'),(peer,peer||'@cache.invalid');
  insert into public.subscriptions(user_id,app_store_original_transaction_id,product_id,status,expires_at)
    values(u,u::text,'fixture','active',now()+interval '1 year');
  reference_path:='users/'||u||'/references/'||ref||'.jpg';
  output_path:='users/'||u||'/studio/'||cached||'/result.png';
  insert into storage.objects(bucket_id,name) values('user-content',reference_path),('user-content',output_path);
  insert into public.studio_allowances(id,user_id,consumed_at,latest_generation_id) values(cached_allowance,u,now(),cached);
  insert into public.studio_generations(id,user_id,reference_image_path,prompt_payload,status,provider,allowance_id,
      result_image_path,cache_key,cache_expires_at,retention_expires_at)
    values(cached,u,reference_path,'{}','complete','mock',cached_allowance,output_path,cache_key,now()+interval '90 days',now()+interval '30 days');

  select * into row from public.find_studio_generation_cache(u,cache_key);
  if row.id<>cached then raise exception 'Complete, retained, present owner result was not reused'; end if;
  if exists(select 1 from public.find_studio_generation_cache(peer,cache_key)) then raise exception 'Peer read a cached result'; end if;

  update public.studio_quota_config set premium_monthly_limit=1;
  before_allowances:=(select count(*) from public.studio_allowances where user_id=u);
  select * into row from public.enqueue_studio_generation_cached(
    u,cache_key,v_request_key,request_hash,reference_path,null,'{}','mock');
  if row.id<>cached then raise exception 'Semantic cache hit created a second generation'; end if;
  if (select count(*) from public.studio_allowances where user_id=u)<>before_allowances then
    raise exception 'Cache hit reserved another allowance'; end if;
  if not exists(select 1 from public.studio_submission_requests where user_id=u and request_key=v_request_key and generation_id=cached) then
    raise exception 'Cache hit did not preserve transport idempotency mapping'; end if;
  begin
    perform * from public.enqueue_studio_generation_cached(
      u,cache_key,v_request_key,encode(extensions.digest('changed request','sha256'),'hex'),reference_path,null,'{}','mock');
    raise exception 'Request key accepted a different payload';
  exception when raise_exception then if sqlerrm<>'studio_request_conflict' then raise; end if; end;

  -- The same complete row is not a hit after its source object disappears,
  -- after output retention expires, or after the semantic TTL expires.
  delete from storage.objects where bucket_id='user-content' and name=output_path;
  if exists(select 1 from public.find_studio_generation_cache(u,cache_key)) then raise exception 'Missing result object was reused'; end if;
  insert into storage.objects(bucket_id,name) values('user-content',output_path);
  update public.studio_generations set retention_expires_at=now()-interval '1 second' where id=cached;
  if exists(select 1 from public.find_studio_generation_cache(u,cache_key)) then raise exception 'Expired retained result was reused'; end if;
  update public.studio_generations set retention_expires_at=now()+interval '30 days',cache_expires_at=now()-interval '1 second' where id=cached;
  if exists(select 1 from public.find_studio_generation_cache(u,cache_key)) then raise exception 'Expired semantic cache entry was reused'; end if;
  update public.studio_generations set cache_expires_at=now()+interval '90 days',deleted_at=now() where id=cached;
  if exists(select 1 from public.find_studio_generation_cache(u,cache_key)) then raise exception 'Soft-deleted generation was reused'; end if;

  update public.studio_quota_config set premium_monthly_limit=20;

  -- A recently queued job may coalesce, but an old pending job and a
  -- generating job whose worker lease expired must not mask fresh work.
  insert into public.studio_allowances(id,user_id) values(pending_allowance,u);
  insert into public.studio_generations(id,user_id,reference_image_path,prompt_payload,status,provider,allowance_id,cache_key,created_at)
    values(pending,u,reference_path,'{}','queued','mock',pending_allowance,reroll_key,now());
  if not exists(select 1 from public.find_studio_generation_cache(u,reroll_key) where id=pending) then
    raise exception 'Fresh queued request was not coalesced'; end if;
  update public.studio_generations set status='generating',claim_token=gen_random_uuid(),claim_expires_at=now()-interval '1 second'
    where id=pending;
  if exists(select 1 from public.find_studio_generation_cache(u,reroll_key)) then
    raise exception 'Expired worker lease was reused'; end if;
  update public.studio_generations set status='queued',created_at=now()-interval '16 minutes',claim_token=null,claim_expires_at=null
    where id=pending;
  if exists(select 1 from public.find_studio_generation_cache(u,reroll_key)) then
    raise exception 'Stale queued request was reused'; end if;
  update public.studio_generations set status='failed',prompt_payload='{}' where id=pending;
  if exists(select 1 from public.find_studio_generation_cache(u,reroll_key)) then
    raise exception 'Failed generation was reused'; end if;

  -- Restore capacity only to exercise that a changed nonce enqueues separately.
  update public.studio_quota_config set premium_monthly_limit=20;
  -- A fresh variation nonce changes the semantic key and enqueues separately.
  select * into row from public.enqueue_studio_generation_cached(
    u,reroll_key,gen_random_uuid(),encode(extensions.digest('reroll request','sha256'),'hex'),reference_path,null,'{}','mock');
  rerolled:=row.id;
  if rerolled in (cached,pending) then raise exception 'Explicit reroll reused an earlier row'; end if;
  if not exists(select 1 from public.studio_generations g where g.id=rerolled and g.cache_key=reroll_key) then
    raise exception 'Explicit reroll was not stored under its distinct cache key'; end if;
  delete from auth.users where id in(u,peer);
end;
$$;
rollback;
