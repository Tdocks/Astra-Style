#!/usr/bin/env python3
"""Exercise reference erasure/save/enqueue races in a disposable astra_ DB."""
import subprocess
import sys
import uuid

database = sys.argv[1] if len(sys.argv) == 2 else ""
if not database.startswith("astra_") or not all(c.isalnum() or c == "_" for c in database):
    raise SystemExit("Supply the astra_ scratch DB created by the RLS harness.")
command = ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-d", database]


def sql(query, *, check=True):
    return subprocess.run(command, input=query, text=True, capture_output=True, check=check)


def hold(query):
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    process.stdin.write("begin;\n" + query + "\nselect 'locked';\n")
    process.stdin.flush()
    assert process.stdout.readline().strip() == "locked", "Fixture failed to acquire its lock"
    return process


def waiting(query, fragment):
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    process.stdin.write(query + "\n")
    process.stdin.close()
    for _ in range(150):
        if sql("select count(*) from pg_stat_activity where datname=current_database() "
               f"and wait_event_type='Lock' and query like '%{fragment}%';").stdout.strip() == "1":
            return process
    process.terminate(); process.wait(timeout=10)
    raise AssertionError("Competing operation never waited on its expected lock")


def commit(process):
    process.stdin.write("commit;\n"); process.stdin.close()
    assert process.wait(timeout=10) == 0, process.stderr.read()


user, parent, child, ref, abandoned = (str(uuid.uuid4()) for _ in range(5))
path = f"users/{user}/references/{ref}.jpg"
orphan = f"users/{user}/references/{abandoned}.jpg"
output = f"users/{user}/studio/{parent}/result.png"
held = None
try:
    sql(f"""insert into auth.users(id,email) values('{user}','{user}@references-concurrency.invalid');
      insert into public.body_profiles(user_id,appearance) values('{user}',jsonb_build_object('reference_selfie_paths',jsonb_build_array('{path}')));
      insert into public.studio_allowances(id,user_id) values('{parent}','{user}'),('{child}','{user}');
      insert into public.studio_generations(id,user_id,reference_image_path,status,result_image_path,allowance_id)
        values('{parent}','{user}','{path}','complete','{output}','{parent}');
      update public.studio_retention_config set enabled=true,reference_cleanup_enabled=true;""")
    held = hold(f"insert into public.studio_generations(id,user_id,reference_image_path,status,allowance_id) values('{child}','{user}','{output}','queued','{child}');")
    deletion = waiting(f"select public.prepare_reference_deletion('{user}','{path}');", "prepare_reference_deletion")
    commit(held); held = None
    assert deletion.wait(timeout=10) != 0
    assert "reference_photo_in_progress" in deletion.stderr.read()
    assert sql(f"select count(*) from public.studio_generations where user_id='{user}' and deleted_at is not null;").stdout.strip() == "0"
    sql(f"update public.studio_generations set status='failed' where id='{child}';")
    held = hold(f"do $$ begin perform public.prepare_reference_deletion('{user}','{path}'); end $$;")
    insertion = waiting(f"insert into public.studio_generations(user_id,reference_image_path,status,allowance_id) values('{user}','{path}','queued','{child}');", "insert into public.studio_generations")
    commit(held); held = None
    assert insertion.wait(timeout=10) != 0
    assert "studio_source_unavailable" in insertion.stderr.read()
    # The profile update holds its row and path guard. A waiting orphan sweep
    # must see that committed save, even though its candidate snapshot was old.
    sql(f"insert into storage.objects(bucket_id,name,created_at,updated_at) values('user-content','{orphan}',now()-interval '2 days',now()-interval '2 days');")
    held = hold(f"update public.body_profiles set appearance=jsonb_build_object('reference_selfie_paths',jsonb_build_array('{orphan}')) where user_id='{user}';")
    sweep = waiting("select public.prepare_reference_retention(25);", "prepare_reference_retention")
    commit(held); held = None
    assert sweep.wait(timeout=10) == 0, sweep.stderr.read()
    assert sweep.stdout.read().strip() == "0"
    # Reverse the ordering: once cleanup owns the path, a stale save must wait
    # and then reject its newly tombstoned photo rather than resurrect it.
    sql(f"update public.body_profiles set appearance=jsonb_build_object('reference_selfie_paths','[]'::jsonb) where user_id='{user}';")
    held = hold("do $$ begin perform public.prepare_reference_retention(25); end $$;")
    save = waiting(f"update public.body_profiles set appearance=jsonb_build_object('reference_selfie_paths',jsonb_build_array('{orphan}')) where user_id='{user}';", "update public.body_profiles")
    commit(held); held = None
    assert save.wait(timeout=10) != 0
    assert "reference_photo_unavailable" in save.stderr.read()
    print("Both reference enqueue/erasure and profile-save/abandoned-cleanup orderings passed.")
finally:
    if held is not None:
        held.terminate(); held.wait(timeout=10)
    sql(f"delete from auth.users where id='{user}'; delete from storage.objects where name like 'users/{user}/%';", check=False)
