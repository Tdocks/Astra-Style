begin;
do $$
declare
  u uuid:=gen_random_uuid();
  peer uuid:=gen_random_uuid();
  free_user uuid:=gen_random_uuid();
  source_id uuid:=gen_random_uuid();
  free_source_id uuid:=gen_random_uuid();
  missing_source_id uuid:=gen_random_uuid();
  missing_reference_id uuid:=gen_random_uuid();
  stale_consent_source_id uuid:=gen_random_uuid();
  reference_photo_id uuid:=gen_random_uuid();
  reference_path text;
  child_id uuid;
  replay_id uuid;
  retry_id uuid;
  allowance uuid;
  blocked boolean;
  source_payload jsonb:='{"mode":"reference","prompt":"preserve exact prompt","resolution":"draft","garments":[{"role":"top","normalizedTitle":"navy merino crew"}],"controls":{"pose":"standing_front"}}';
begin
  reference_path:='users/'||u||'/references/'||reference_photo_id||'.jpg';
  insert into auth.users(id,email) values
    (u,u||'@hires.invalid'),(peer,peer||'@hires.invalid'),(free_user,free_user||'@hires.invalid');
  insert into storage.objects(bucket_id,name,owner,metadata) values
    ('user-content',reference_path,u,'{"mimetype":"image/jpeg"}');
  insert into public.body_profiles(user_id,appearance) values
    (u,jsonb_build_object('reference_selfie_paths',jsonb_build_array(reference_path)));
  insert into public.subscriptions(user_id,app_store_original_transaction_id,product_id,status,expires_at)
    values(u,u::text,'fixture','active',now()+interval '1 year');
  insert into public.studio_allowances(id,user_id,consumed_at) values(source_id,u,now()) returning id into allowance;
  insert into public.studio_generations(
    id,user_id,reference_image_path,prompt_payload,status,result_image_path,provider,allowance_id,retention_expires_at
  ) values(
    source_id,u,reference_path,source_payload,'complete',
    'users/'||u||'/studio/'||source_id||'/result.png','fixture',allowance,now()+interval '1 day'
  );
  insert into storage.objects(bucket_id,name,owner,metadata) values
    ('user-content','users/'||u||'/studio/'||source_id||'/result.png',u,'{"mimetype":"image/png"}');
  insert into public.studio_allowances(id,user_id,consumed_at) values(free_source_id,free_user,now());
  insert into public.studio_generations(
    id,user_id,reference_image_path,prompt_payload,status,result_image_path,provider,allowance_id,retention_expires_at
  ) values(
    free_source_id,free_user,'','{"mode":"inspiration","prompt":"flat lay","resolution":"draft"}',
    'complete','users/'||free_user||'/studio/'||free_source_id||'/result.png','fixture',free_source_id,now()+interval '1 day'
  );
  insert into storage.objects(bucket_id,name,owner,metadata) values
    ('user-content','users/'||free_user||'/studio/'||free_source_id||'/result.png',free_user,'{"mimetype":"image/png"}');
  insert into storage.objects(bucket_id,name,owner,metadata) values
    ('user-content','users/'||u||'/studio/'||missing_reference_id||'/result.png',u,'{"mimetype":"image/png"}');
  insert into storage.objects(bucket_id,name,owner,metadata) values
    ('user-content','users/'||u||'/studio/'||stale_consent_source_id||'/result.png',u,'{"mimetype":"image/png"}');

  perform set_config('role','service_role',true);
  select id into child_id from public.enqueue_studio_hi_res_export(
    u,source_id,'fixture',true,'2026-08-17'
  );
  select id into replay_id from public.enqueue_studio_hi_res_export(
    u,source_id,'fixture',true,'2026-08-17'
  );
  if child_id is null or replay_id<>child_id then raise exception 'Hi-res export replay made another job'; end if;
  if (select count(*) from public.studio_allowances where user_id=u)<>2 then
    raise exception 'Hi-res export did not consume exactly one existing Studio allowance';
  end if;
  insert into public.studio_generations(
    id,user_id,reference_image_path,prompt_payload,status,result_image_path,provider,allowance_id,retention_expires_at
  ) values(
    missing_source_id,u,'','{"mode":"inspiration","prompt":"missing object","resolution":"draft"}',
    'complete','users/'||u||'/studio/'||missing_source_id||'/result.png','fixture',allowance,now()+interval '1 day'
  );
  blocked:=false;
  begin perform public.enqueue_studio_hi_res_export(u,missing_source_id,'fixture',false,null);
  exception when others then if sqlerrm='studio_export_source_unavailable' then blocked:=true; else raise; end if; end;
  if not blocked or (select count(*) from public.studio_allowances where user_id=u)<>2 then
    raise exception 'Missing source object was accepted or reserved a new allowance';
  end if;
  insert into public.studio_generations(
    id,user_id,reference_image_path,prompt_payload,status,result_image_path,provider,allowance_id,retention_expires_at
  ) values(
    missing_reference_id,u,'users/'||u||'/references/'||gen_random_uuid()||'.jpg',source_payload,'complete',
    'users/'||u||'/studio/'||missing_reference_id||'/result.png','fixture',allowance,now()+interval '1 day'
  );
  blocked:=false;
  begin perform public.enqueue_studio_hi_res_export(u,missing_reference_id,'fixture',true,'2026-08-17');
  exception when others then if sqlerrm='studio_export_source_unavailable' then blocked:=true; else raise; end if; end;
  if not blocked or (select count(*) from public.studio_allowances where user_id=u)<>2 then
    raise exception 'Deleted reference photo was accepted or reserved a new allowance';
  end if;
  blocked:=false;
  begin perform public.enqueue_studio_hi_res_export(free_user,free_source_id,'mock',false,null);
  exception when others then if sqlerrm='studio_hi_res_provider_unavailable' then blocked:=true; else raise; end if; end;
  if not blocked or (select count(*) from public.studio_allowances where user_id=free_user)<>1 then
    raise exception 'Mock provider was allowed to spend a reservation';
  end if;
  blocked:=false;
  begin perform public.enqueue_studio_hi_res_export(free_user,free_source_id,'fixture',false,null);
  exception when others then if sqlerrm='studio_hi_res_premium_required' then blocked:=true; else raise; end if; end;
  if not blocked or (select count(*) from public.studio_allowances where user_id=free_user)<>1 then
    raise exception 'Free user exported high resolution or spent an allowance';
  end if;
  blocked:=false;
  insert into public.studio_generations(
    id,user_id,reference_image_path,prompt_payload,status,result_image_path,provider,allowance_id,retention_expires_at
  ) values(
    stale_consent_source_id,u,reference_path,source_payload,'complete',
    'users/'||u||'/studio/'||stale_consent_source_id||'/result.png','fixture',allowance,now()+interval '1 day'
  );
  blocked:=false;
  begin perform public.enqueue_studio_hi_res_export(u,stale_consent_source_id,'fixture',true,'2020-01-01');
  exception when others then if sqlerrm='studio_export_consent_required' then blocked:=true; else raise; end if; end;
  if not blocked then raise exception 'Stale/missing fresh consent was accepted'; end if;
  if not exists(select 1 from public.studio_generations where id=child_id and hi_res_source_id=source_id
    and reference_image_path=reference_path
    and prompt_payload->>'prompt'='preserve exact prompt' and prompt_payload->>'resolution'='hi_res'
    and prompt_payload#>>'{hi_res_export_consent,terms_version}'='2026-08-17') then
    raise exception 'Hi-res child did not preserve source context and fresh consent';
  end if;
  if (select prompt_payload->>'resolution' from public.studio_generations where id=source_id)<>'draft' then
    raise exception 'Hi-res export mutated the draft source';
  end if;
  blocked:=false;
  update public.studio_generations set prompt_payload=jsonb_set(prompt_payload,'{resolution}','"hi_res"'::jsonb)
    where id=source_id;
  begin perform public.enqueue_studio_hi_res_export(u,source_id,'fixture',true,'2026-08-17');
  exception when others then if sqlerrm='studio_export_source_unavailable' then blocked:=true; else raise; end if; end;
  if not blocked then raise exception 'Hi-res export source was eligible for a second hi-res render'; end if;
  update public.studio_generations set prompt_payload=jsonb_set(prompt_payload,'{resolution}','"draft"'::jsonb)
    where id=source_id;
  update public.studio_generations set status='failed',result_image_path=null,
    prompt_payload=prompt_payload||'{"is_retryable_failure":true}'::jsonb
    where id=child_id;
  select id into retry_id from public.enqueue_studio_generation(
    u,reference_path,null,
    (select prompt_payload from public.studio_generations where id=child_id),'fixture',child_id
  );
  if retry_id is null or not exists(select 1 from public.studio_generations
    where id=retry_id and hi_res_source_id=source_id) then
    raise exception 'Retry lost its hi-res source dependency';
  end if;
  select id into replay_id from public.enqueue_studio_hi_res_export(u,source_id,'fixture',true,'2026-08-17');
  if replay_id<>retry_id then raise exception 'Export replay did not return latest retry'; end if;
  if (select count(*) from public.studio_allowances where user_id=u)<>2 then
    raise exception 'Hi-res retry reserved a second allowance';
  end if;
  blocked:=false;
  begin
    perform public.enqueue_studio_hi_res_export(peer,source_id,'fixture',true,'2026-08-17');
  exception when others then if sqlerrm='studio_export_source_unavailable' then blocked:=true; else raise; end if; end;
  if not blocked then raise exception 'Peer source was exportable'; end if;

  -- The child protects the source from both expiry and explicit erasure.
  update public.studio_generations set retention_expires_at=now()-interval '1 second' where id=source_id;
  update public.studio_retention_config set enabled=true where singleton;
  if public.prepare_studio_retention(100)<>0 then raise exception 'Dependent draft expired before its hi-res child'; end if;
  blocked:=false;
  begin perform public.enqueue_studio_hi_res_export(u,source_id,'fixture',true,'2026-08-17');
  exception when others then if sqlerrm='studio_export_source_unavailable' then blocked:=true; else raise; end if; end;
  if not blocked then raise exception 'Expired draft source accepted a new export'; end if;
  blocked:=false;
  begin perform public.prepare_studio_deletion(u,source_id);
  exception when others then if sqlerrm='studio_delete_has_variations' then blocked:=true; else raise; end if; end;
  if not blocked then raise exception 'Source deletion ignored live hi-res dependency'; end if;
end;
$$;
rollback;
