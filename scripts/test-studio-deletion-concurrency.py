#!/usr/bin/env python3
"""Run after run-rls-tests.sh --keep-db, against a disposable scratch DB only."""
import subprocess
import sys
import uuid

database = sys.argv[1] if len(sys.argv) == 2 else ""
if not database.startswith("astra_") or not all(c.isalnum() or c == "_" for c in database):
    raise SystemExit("Supply the astra_ scratch database created by the RLS harness.")
command = ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-d", database]


def sql(query, *, check=True):
    return subprocess.run(command, input=query, text=True, capture_output=True, check=check)


def held_transaction(query):
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    process.stdin.write("begin;\n" + query + "\nselect 'locked';\n")
    process.stdin.flush()
    assert process.stdout.readline().strip() == "locked", "Fixture did not acquire the source lock"
    return process


user, parent, child = (str(uuid.uuid4()) for _ in range(3))
path = f"users/{user}/studio/{parent}/result.png"
held = None
try:
    sql(f"""insert into auth.users(id,email) values('{user}','{user}@concurrency.invalid');
      insert into public.studio_allowances(id,user_id) values('{parent}','{user}'),('{child}','{user}');
      insert into public.studio_generations(id,user_id,status,reference_image_path,result_image_path,allowance_id,retention_expires_at)
        values('{parent}','{user}','complete','','{path}','{parent}',now()-interval '1 day');
      update public.studio_retention_config set enabled=true;""")
    # An uncommitted child already holds the parent's lock through its source
    # guard. Manual deletion must wait and then see that committed child.
    held = held_transaction(f"""insert into public.studio_generations(id,user_id,status,reference_image_path,allowance_id)
        values('{child}','{user}','queued','{path}','{child}');""")
    deletion = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    deletion.stdin.write(f"select public.prepare_studio_deletion('{user}','{parent}');\n")
    deletion.stdin.close()
    # Use the server's current wait event as the barrier, not a guessed delay.
    for _ in range(100):
        waiting = sql("select count(*) from pg_stat_activity where datname=current_database() and wait_event_type='Lock' and query like '%prepare_studio_deletion%';").stdout.strip()
        if waiting == "1":
            break
    else:
        raise AssertionError("Deletion never waited on the source lock")
    held.stdin.write("commit;\n"); held.stdin.close()
    assert held.wait(timeout=10) == 0, held.stderr.read()
    held = None
    assert deletion.wait(timeout=10) != 0
    assert "studio_delete_has_variations" in deletion.stderr.read()
    assert sql(f"select deleted_at is null from public.studio_generations where id='{parent}';").stdout.strip() == "t"
    assert sql("select public.prepare_studio_retention(25);").stdout.strip() == "0"
    # Reverse the race: after deletion locks and hides the source, an insertion
    # waiting on it must recheck the current row and reject that source.
    sql(f"delete from public.studio_generations where id='{child}';")
    held = held_transaction(f"do $$ begin perform public.prepare_studio_deletion('{user}','{parent}'); end $$;")
    insertion = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    insertion.stdin.write(f"insert into public.studio_generations(id,user_id,status,reference_image_path,allowance_id) values('{child}','{user}','queued','{path}','{child}');\n")
    insertion.stdin.close()
    for _ in range(100):
        waiting = sql("select count(*) from pg_stat_activity where datname=current_database() and wait_event_type='Lock' and query like 'insert into public.studio_generations%';").stdout.strip()
        if waiting == "1":
            break
    else:
        raise AssertionError("Insertion never waited on the deletion lock")
    held.stdin.write("commit;\n"); held.stdin.close()
    assert held.wait(timeout=10) == 0, held.stderr.read()
    held = None
    assert insertion.wait(timeout=10) != 0
    assert "studio_source_unavailable" in insertion.stderr.read()
    print("Both concurrent source-insert/delete orderings passed; automatic expiry also preserved the dependent source.")
finally:
    if held is not None:
        held.terminate(); held.wait(timeout=10)
    sql(f"delete from auth.users where id='{user}';", check=False)
