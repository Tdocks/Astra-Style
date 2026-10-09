-- Scratch-only integration checks for the additive taste-answer migration.
-- Execute after all migrations and the test-only auth/storage shim/grants.
-- The surrounding transaction rolls back all disposable auth/profile rows.
begin;

create temp table taste_test_users (label text primary key, id uuid not null) on commit drop;
insert into taste_test_users values
  ('a', '52000000-0000-0000-0000-000000000001'),
  ('b', '52000000-0000-0000-0000-000000000002'),
  ('c', '52000000-0000-0000-0000-000000000003');
insert into auth.users (id, email)
select id, label || '@taste-refinement-test.astrastyle.invalid' from taste_test_users;

reset role;
do $$
declare
  v_proc regprocedure := 'public.complete_onboarding(jsonb,jsonb,jsonb,text)'::regprocedure;
  v_secdef boolean;
  v_config text[];
begin
  select prosecdef, proconfig into v_secdef, v_config from pg_proc where oid = v_proc;
  if v_secdef then raise exception 'complete_onboarding must remain SECURITY INVOKER'; end if;
  if v_config is null or not ('search_path=""' = any(v_config)) then
    raise exception 'complete_onboarding lost empty search_path: %', v_config;
  end if;
  if has_function_privilege('anon', v_proc, 'EXECUTE') then
    raise exception 'anon unexpectedly has complete_onboarding EXECUTE';
  end if;
  if not has_function_privilege('authenticated', v_proc, 'EXECUTE') then
    raise exception 'authenticated lost complete_onboarding EXECUTE';
  end if;
end
$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
do $$
begin
  begin
    perform public.complete_onboarding('{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'menswear_3_role');
    raise exception 'complete_onboarding unexpectedly accepted a missing auth.uid()';
  exception when sqlstate '28000' then null;
  end;
end
$$;
reset role;

-- Seed peer B's style row through the same RPC before testing A's RLS view.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"52000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select public.complete_onboarding('{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'menswear_3_role');
reset role;

-- Caller A supplies peer B's id in JSON. Identity still comes from auth.uid().
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"52000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select public.complete_onboarding(
  '{"user_id":"52000000-0000-0000-0000-000000000002","preference_vector":{"version":1,"comparisons_answered":2,"comparisons_offered":16,"dimensions":{"formality":{"score":0.75,"confidence":"moderate","observations":2,"agreement":1}}},"preference_quiz_answers":[{"pair_id":"formality-01","chosen_option_id":"tailored"},{"pair_id":"colour-01","chosen_option_id":"no_preference"}]}'::jsonb,
  '{}'::jsonb, '{}'::jsonb, 'menswear_3_role'
);
do $$
declare
  v_a uuid := '52000000-0000-0000-0000-000000000001';
  v_b uuid := '52000000-0000-0000-0000-000000000002';
  v_answers jsonb;
  v_count integer;
begin
  select preference_quiz_answers into v_answers from public.style_profiles where user_id = v_a;
  if v_answers <> '[{"pair_id":"formality-01","chosen_option_id":"tailored"},{"pair_id":"colour-01","chosen_option_id":"no_preference"}]'::jsonb then
    raise exception 'RPC did not persist exact quiz answers: %', v_answers;
  end if;
  select count(*) into v_count from public.style_profiles where user_id = v_b;
  if v_count <> 0 then raise exception 'RPC accepted a client-selected peer owner'; end if;
  select count(*) into v_count from public.body_profiles where user_id = v_a;
  if v_count <> 1 then raise exception 'RPC did not atomically write body profile'; end if;
  select count(*) into v_count from public.lifestyle_profiles where user_id = v_a;
  if v_count <> 1 then raise exception 'RPC did not atomically write lifestyle profile'; end if;
  select count(*) into v_count from public.style_profiles where user_id = v_b;
  if v_count <> 0 then raise exception 'User A can read peer B style profile'; end if;
  update public.style_profiles set preference_quiz_answers = '[]'::jsonb where user_id = v_b;
  get diagnostics v_count = row_count;
  if v_count <> 0 then raise exception 'User A updated peer B style profile'; end if;
end
$$;

-- Old callers omit the key; the added column defaults to an empty array.
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"52000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select public.complete_onboarding('{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'menswear_3_role');
do $$
declare v_answers jsonb;
begin
  select preference_quiz_answers into v_answers from public.style_profiles
  where user_id = '52000000-0000-0000-0000-000000000002';
  if v_answers <> '[]'::jsonb then
    raise exception 'Legacy onboarding payload did not default answers to []: %', v_answers;
  end if;
end
$$;

-- Database constraint rejects overlong records; transaction rollback prevents
-- any of the preceding profile-table writes for caller C from surviving.
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"52000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
do $$
declare
  v_too_many jsonb := '[]'::jsonb;
  v_count integer;
  i integer;
begin
  for i in 1..21 loop
    v_too_many := v_too_many || jsonb_build_array(jsonb_build_object(
      'pair_id', 'pair-' || i, 'chosen_option_id', 'a'
    ));
  end loop;
  begin
    perform public.complete_onboarding(
      jsonb_build_object('preference_quiz_answers', v_too_many), '{}'::jsonb, '{}'::jsonb, 'menswear_3_role'
    );
    raise exception '21 quiz answers unexpectedly passed the database constraint';
  exception when check_violation then null;
  end;
  select count(*) into v_count from public.style_profiles
  where user_id = '52000000-0000-0000-0000-000000000003';
  if v_count <> 0 then raise exception 'Rejected quiz write left partial style profile'; end if;
  select count(*) into v_count from public.body_profiles
  where user_id = '52000000-0000-0000-0000-000000000003';
  if v_count <> 0 then raise exception 'Rejected quiz write left partial body profile'; end if;
  select count(*) into v_count from public.lifestyle_profiles
  where user_id = '52000000-0000-0000-0000-000000000003';
  if v_count <> 0 then raise exception 'Rejected quiz write left partial lifestyle profile'; end if;
end
$$;

do $$ begin
  raise notice 'Taste quiz answers persistence, ownership, legacy compatibility, grants and atomic rollback passed';
end $$;

rollback;
